#!/usr/bin/env perl

=pod

=head1 NAME

dequeuer.pl

=head1 DESCRIPTION

a script that dequeue and submit a limited number of jobs
(depending on JOB_LIMIT in BatchQueue) from a MySQL based priority queue
(QUEUE_HOST and QUEUE_NAME) into the LSF farm queue. The jobs are progressively
added in the MySQL queue by the pipeline rulemanager scripts.

=head1 SYNOPSIS

The MySQL queue is a single table that orders the jobs by job's priority
and by job's creation date. A job object can be recovered from the
pipeline database with the parameters 'job_id', 'host' and 'pipeline'.
Note that, the pipeline database and queue connexion parameters
(login, password and port) are fetched from the ~/.netrc file.
See the Net::Netrc module for more details.

=head1 OPTIONS

	-help|h		displays this documentation with PERLDOC
	-verbose	print the submission and update info
	-sleep		this is the amount of time the script will sleep for
			after each loop and wait for free slots (default: 180s)
	-flush		flush the jobs batch queues after this number of loop (default: 30)
	-check		check the status of the pipeline jobs after this number of loops (default: 100)
	-fetch_number	number of jobs fetched from the database queue, pipe_queue (default: 100)
	-analysis 	a logic_name of an analysis you want to dequeue and submit.
			If you specify this option you will only submit this analysis
			or analyses as the option can appear on the command line
			multiple times
  	-skip_analysis	a logic_name of an analysis you don't want to dequeue and
  			submit. If this option is specified these are the only
  			analyses which won't be submit
	-ana_regex 	dequeue and submit analysis logic_name that matches this regular expression
  	-skip_ana_regex	skip analysis logic_name that matches this regular expression
  	-pipeline	only dequeue jobs stored in this pipeline(s)
  	-skip_pipeline	don't dequeue jobs stored in this pipeline(s)
  	-host		only dequeue jobs stored on this host(s)
  	-skip_host	don't dequeue jobs stored on this host(s)
  	-skip_update don't run any update jobs

These arguments are overridable configurations
options from Bio::EnsEMBL::Pipeline::Config::BatchQueue.pm

	-queue_manager		this specifies which
				Bio::EnsEMBL::Pipeline::BatchSubmission module is used
	-job_limit		the maximun number of jobs of the specified status allowed in the
	 			system
	-queue_name		database name of the MySQL based priority queue
	-queue_host		host name of the queue

=head1 SEE ALSO

rulemanager.pl in ensembl-pipeline/scripts/Finished

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use warnings ;
use strict;
use Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor;
use Bio::EnsEMBL::Pipeline::Config::General;
use Bio::EnsEMBL::Pipeline::Config::BatchQueue;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use DBI;
use Bio::EnsEMBL::Pipeline::Finished::PipeQueue;
use Net::Netrc;
use Sys::Hostname;
use Getopt::Long;

my $job_id;
my $queue_manager;
my $verbose = 0;
my $job_limit;
my $job_limit_add_running = 1; # true "no more than job_limit RUNning", false "aim for job_limit PENDing"
my $queue_host;
my $queue_name;
my $sleep = 180;
my $flush = 30; # batch queue flush frequency: n => flush the batch queue once every n loops
my $check = 100; # job status check frequency
my $fetch_number = 100;
my @analysis_to_run;
my @analysis_to_skip;
my $analysis_regex_skip;
my $analysis_regex_run;
my @pipeline_to_run;
my @pipeline_to_skip;
my @host_to_run;
my @host_to_skip;
my $db_adaptors;
my $skip_update = 0;

my @PIPE_HOST = qw/otterpipe1 otterpipe2/;

my %AWOL_VALID_STATUS = map{$_, 1}
	('SUBMITTED', 'RUNNING', 'READING','WRITING', 'WAITING','AWOL');

my $usage = sub { exec( 'perldoc', $0 ); };

$SIG{TERM} = \&termhandler;
$SIG{INT}  = \&termhandler;
$SIG{USR1} = \&wakehandler;
set_joblim_handler(USR2 => 0);


GetOptions(
	'verbose!'        => \$verbose,
	'job_limit=s'     => \$job_limit,
	'queue_manager=s' => \$queue_manager,
	'queue_name=s'    => \$queue_name,
	'queue_host=s'    => \$queue_host,
	'sleep=s'		  => \$sleep,
	'flush=s'		  => \$flush,
	'check=s'		  => \$check,
	'fetch_number=s'  => \$fetch_number,
	'analysis|logic_name=s@' => \@analysis_to_run,
	'skip_analysis=s@'       => \@analysis_to_skip,
	'ana_regex=s' => \$analysis_regex_run,
	'skip_ana_regex=s'       => \$analysis_regex_skip,
	'pipeline=s@'		=> \@pipeline_to_run,
	'skip_pipeline=s@'       => \@pipeline_to_skip,
	'host=s@'		=> \@host_to_run,
	'skip_host=s@'       => \@host_to_skip,
	'skip_update!'      => \$skip_update,
	'h|help!'         => $usage

  )
  or die("Couldn't get options");

$job_limit     = $JOB_LIMIT     unless ($job_limit);
$queue_manager = $QUEUE_MANAGER unless ($queue_manager);
$queue_host    = $QUEUE_HOST    unless ($queue_host);
$queue_name    = $QUEUE_NAME    unless ($queue_name);
Bio::EnsEMBL::Pipeline::Finished::PipeQueue->configure($queue_host, $queue_name);

@analysis_to_run = map {split/,/} @analysis_to_run ;
@analysis_to_skip = map {split/,/} @analysis_to_skip ;
@pipeline_to_run = map {split/,/} @pipeline_to_run ;
@pipeline_to_skip = map {split/,/} @pipeline_to_skip ;
@host_to_run = map {split/,/} @host_to_run ;
@host_to_skip = map {split/,/} @host_to_skip ;

# Job fetch statement handle
my $sql_fetch = qq(SELECT id, created, priority, job_id, host, pipeline, analysis, is_update FROM queue);
my @where = ();
if(@analysis_to_run) {
  my $ana_string = join("', '", @analysis_to_run);
  push @where, "analysis IN ('$ana_string')";
}
if(@analysis_to_skip) {
  my $skip_ana_string = join("', '", @analysis_to_skip);
  push @where, "analysis NOT IN ('$skip_ana_string')";
}
if($analysis_regex_run) {
  my $ana_string = join("', '", @analysis_to_run);
  push @where, "analysis LIKE '%${analysis_regex_run}%'";
}
if($analysis_regex_skip) {
  my $skip_ana_string = join("', '", @analysis_to_skip);
  push @where, "analysis NOT LIKE '%${analysis_regex_skip}%'";
}
if(@pipeline_to_run) {
  my $pipe_string = join("', '", @pipeline_to_run);
  push @where, "pipeline IN ('$pipe_string')";
}
if(@pipeline_to_skip) {
  my $skip_pipe_string = join("', '", @pipeline_to_skip);
  push @where, "pipeline NOT IN ('$skip_pipe_string')";
}
if(@host_to_run) {
  my $host_string = join("', '", @host_to_run);
  push @where, "host IN ('$host_string')";
}
if(@host_to_skip) {
  my $skip_host_string = join("', '", @host_to_skip);
  push @where, "host NOT IN ('$skip_host_string')";
}
if ($skip_update) {
    push(@where, "is_update = 0")
}
if(scalar(@where)) {
    $sql_fetch .= ' WHERE '.join(' AND ', @where);
}
$sql_fetch .= " ORDER BY priority DESC, md5(id)/*kinda-shuffle*/  LIMIT ? ";

my $fetch; # sth obtained on demand


# Job delete statement handle
my $delete; # sth obtained on demand
my $delete_sql = qq{
		DELETE FROM queue
		WHERE id = ?
	};

# Unbuffered output
{
    my $old = select STDERR;
    $| = 1;
    select $old;
    $| = 1;
}

# Load the BatchSubmission module (LSF)
my $batch_q_module = "Bio::EnsEMBL::Pipeline::BatchSubmission::$queue_manager";
my $file           = "$batch_q_module.pm";
$file =~ s{::}{/}g;
eval { require "$file"; };
if ($@) {
	print STDERR "Error trying to load $batch_q_module;\ncan't find $file\n";
	exit 1;
}
my $batch_q_object = $batch_q_module->new();

my $loop = 1;
# The main loop
while ($loop) {
	my $free_slots = &job_stats( $loop%$check == 0 || $loop == 1 );
	&flush_queue( $free_slots );
	&flush_batch() if( $loop%$flush == 0 );
        if ($verbose) {
            my $until = localtime(time() + $sleep);
            print "Finished for now (loop $loop), going to sleep for $sleep secs until $until\n";
        }
        sleep($sleep) if $loop;
        $loop++ if $loop;
}
&flush_batch();
print "Exit DQdequeuer ....\n" if $verbose;
exit 0;


## signal handlers

sub termhandler {
    my ($sig) = @_;
    undef $SIG{$sig};
    warn "Caught SIG$sig - another to abend\n";
    $loop = 0;
}
sub wakehandler {
    my ($sig) = @_;
    $SIG{$sig} = \&wakehandler;
    warn "Caught SIG$sig - waking up\n";
}
sub set_joblim_handler {
    my ($sig, $next_joblim) = @_;
    $SIG{$sig} = sub {
        my ($sig) = @_;
        set_joblim_handler($sig, $job_limit);
        $next_joblim = 1 if $job_limit <= 0 && $next_joblim <= 0;
        warn "Caught SIG$sig - set job_limit=$next_joblim; again to restore $job_limit\n";
        $job_limit = $next_joblim;
    };
}


## methods

# flush the batch jobs
sub flush_batch {
	print "Flushing the batch queues ....\n" if $verbose;
	foreach my $host ( keys %$db_adaptors ) {
		foreach my $dbname ( keys %{ $db_adaptors->{$host} } ) {
			print "\tpipeline $host -> $dbname\n" if $verbose;
			my $job_adaptor =
			  $db_adaptors->{$host}->{$dbname}->get_JobAdaptor();
			my ($a_job) = $job_adaptor->fetch_by_Status("CREATED",1,1);
			($a_job) = $job_adaptor->fetch_by_Status("CREATED") unless($a_job) ;
			if ($a_job) {
				$a_job->flush_runs($job_adaptor,'',$verbose);
			}
		}
	}
}

# remove a certain number of jobs from the queue
# and submit them into the farm
sub flush_queue {
	my ($slots) = @_;

	SLOT:while($slots) {

		Bio::EnsEMBL::Pipeline::Finished::PipeQueue->ensure_sth(\$fetch, $sql_fetch);

		my $rv = $fetch->execute($fetch_number);
                if (!$rv) {
                    my $err = $fetch->errstr;
                    warn "Fetch from pipe_queue.queue failed: $err; try again later";
                    undef $fetch;
                    last SLOT;
                    # not keen to die here, because we may have cleanup to do
                }
		if($fetch->rows == 0){
			print "No job in queue\n";
			last SLOT;
		}
		JOB:while ( my @row = $fetch->fetchrow_array ) {
			my ( $id, $created, $priority, $job_id, $host, $pipe_name, $analysis, $update ) =
			  @row[ 0 .. 7 ];
			my $submitted = 0;
			my $job = &get_job_from_db( $job_id, $pipe_name, $host );
			if ($job) {
				$job->priority($priority);
				$job->update($update);

				eval {
					$submitted = $job->batch_runRemote;
					my $location = $submitted ? 'LSF':'BATCH';
					print "\t$location\tsubmitted job " . $job_id
					  . " ${host}/${pipe_name} ".$job->analysis->logic_name."\tpriority "
					  . $priority . "\n"
					  if $verbose;
				};
				if ($@) {
					# note, $job->flush_runs eats some errors
					warn(   "ERROR running job "
						  . $job->dbID . " "
						  . $job->analysis->logic_name . " "
						  . $job->stderr_file
						  . " [$@]" );
				}
				else {
					&delete_job($id);
				}
			}
			else {
				warn(   "Job " . $job_id
					  . " not in database "
					  . $host . "/"
					  . $pipe_name );
				&delete_job($id);
			}
			$slots-- if $submitted;
			last SLOT unless $slots # stop if $slots all used
                          && $job_limit && $loop; # these may go to zero asynchronously
		}
	}
}

# Get some stats about farm jobs
sub job_stats {
	my ($update_job) = @_;

	# Do job_stats call before getting jobs
	if ( !$batch_q_object->can('job_stats') ) {
		throw( $batch_q_object . " doesn't have the job_stats method" );
	}
	my %statuses_to_count = map { $_, 1 } @{$JOB_STATUSES_TO_COUNT};   #found in
	       #BatchQueue.pm
	my %job_stats = %{ $batch_q_object->job_stats };

	my $global_job_count = 0;    # job count for all pipelines

	&update_job_status(\%job_stats) if $update_job;

        my $fillup_type = 'Pending';
        if ($job_limit_add_running) {
            # On this code path, I want to limit the number of RUNning
            # jobs on the farm.  Too many uniprots will cause lustre
            # IO problems.  LSF could maybe limit this using another
            # token bucket?
            $statuses_to_count{RUN} = 1;
            $fillup_type .= ' or running';
        } # else N jobs PENDing: ensure the queue never runs dry - throttle wide open!
  GLOBAL: foreach my $sub_id ( keys %job_stats ) {
		if ( $statuses_to_count{ $job_stats{$sub_id} } ) {
			$global_job_count++;
		}
	}

	print "$global_job_count / $job_limit $fillup_type jobs in the farm\n"
	  if ($verbose);

	my $free_slots = $job_limit - $global_job_count; # number of free farm slots
	$free_slots =
	    $free_slots > 0
	  ? $free_slots
	  : 0;    # total nb. of jobs must not exceeds job limit
	print "$free_slots slots available\n" if $verbose;
	return $free_slots;
}

sub update_job_status {
	my ($bjobs_hash) = @_;
	print STDOUT "Updating Pipeline Job Status\n" if $verbose;
	HOST: foreach my $host (@PIPE_HOST) {
		print STDOUT ('-'x50)."\n$host\n" if $verbose;
		my $sth = &get_dbi("",$host)->prepare("SHOW DATABASES LIKE 'pipe_%'");
		$sth->execute;
		PIPE: while(my ($pipe) = $sth->fetchrow_array){
			print "\t$pipe\n" if $verbose;
			my $dba = &get_db_adaptor($pipe,$host);
			my @jobs = $dba->get_JobAdaptor->fetch_by_Status_not_like('CREATED');
			JOB: foreach my $job (@jobs) {
				if ( !$bjobs_hash->{ $job->submission_id } ) {
					my $db_status = $job->current_status->status;
					if($AWOL_VALID_STATUS{$db_status}){
						my $status = &status_from_output($job) || 'AWOL';
						if($status ne $db_status){
							print "Job ".$job->dbID." ".$job->analysis->logic_name
							." status $db_status changed to $status\n" if $verbose;
							$job->set_status($status);
						}
					}
				}
			}
		}
	}
}

sub get_job_from_db {
	my ( $job_id, $pipe_name, $host ) = @_;
	my $job_adaptor = &get_db_adaptor( $pipe_name, $host )->get_JobAdaptor();
	return $job_adaptor->fetch_by_dbID($job_id);
}

sub get_db_adaptor {
	my ( $dbname, $dbhost ) = @_;
	if ( $db_adaptors->{$dbhost}->{$dbname} ) {
		return $db_adaptors->{$dbhost}->{$dbname};
	}
	my ( $dbuser, $dbpass, $dbport ) = &get_db_param( $dbhost );

	my $db = Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor->new(
		-host   => $dbhost,
		-user   => $dbuser,
		-dbname => $dbname,
		-pass   => $dbpass,
		-port   => $dbport
	  )
	  or die(
"Failed to create Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor to db $dbname \n"
	  );

	$db_adaptors->{$dbhost}->{$dbname} = $db;

        $db->dbc->reconnect_when_lost(1);

        # Yet more "are we still connected?"
# hopefully don't need this
#        unless ($db->dbc->db_handle->ping) {
#            my ($cls, $dbname) = (ref($db), $db->dbc->dbname);
#            warn "$cls($dbname) doesn't ping\n";
#            $db->dbc->reconnect;
#            die "Still not connected" unless $db->dbc->db_handle->ping;
#        }

	return $db;
}

sub get_dbi {
	my ( $dbname, # vestigial
             $dbhost ) = @_;
	my ( $dbuser, $dbpass, $dbport ) = &get_db_param( $dbhost );
	my $dsn = "DBI:mysql:host=$dbhost;dbname=$dbname;port=$dbport";

	return DBI->connect( $dsn, $dbuser, $dbpass );
}

sub get_db_param {
	my ( $dbhost ) = @_;
	my ( $dbuser, $dbpass, $dbport );

	my $ref = Net::Netrc->lookup($dbhost);
	throw("$dbhost entry is missing from ~/.netrc") unless ($ref);
	$dbuser = $ref->login;
	$dbpass = $ref->password;
	$dbport = $ref->account;
	throw(
		"Missing parameter in the ~/.netrc file:\n
			machine " .  ( $dbhost || 'missing' ) . "\n
			login " .    ( $dbuser || 'missing' ) . "\n
			password " . ( $dbpass || 'missing' ) . "\n
			account "
		  . ( $dbport || 'missing' )
		  . " (should be used to set the port number)"
	  )
	  unless ( $dbuser && $dbpass && $dbport );

	return ( $dbuser, $dbpass, $dbport );
}

sub delete_job {
	my ($id) = @_;

        Bio::EnsEMBL::Pipeline::Finished::PipeQueue->ensure_sth(\$delete, $delete_sql);
        my $rv = $delete->execute($id);
        if (!$rv) {
            # If the delete fails, dequeuer may run amuck and create
            # an LSF job per second
            die "Delete failed, aborting: SQL=qq{$delete_sql} id=$id err=".$delete->errstr;
        }

        return $rv;
}

sub status_from_output {
	my ( $job ) = @_;
	my $out_file = $job->stdout_file;
	my $status;
	eval {
		if ( -e $out_file ) {
			open( my $F, "<$out_file" );
			while (<$F>) {
				if (/TERM_MEMLIMIT/) { $status = 'OUT_OF_MEMORY'; last; }
				if (/TERM_RUNLIMIT/) { $status = 'RUNTIME_LIMIT'; last; }
			}
			close($F);
		}
	};
	print STDERR "ERROR [$@]\n" if ( $@ && $verbose );

	return $status;
}

