#
# Object for storing details of an analysis job
#
# Cared for by Michele Clamp  <michele@sanger.ac.uk>
#
# Copyright Michele Clamp
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Pipeline::DBSQL::Job

=head1 SYNOPSIS

=head1 DESCRIPTION

Stores run and status details of an analysis job

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::EnsEMBL::Pipeline::DBSQL::Job;
use Data::Dumper;

use vars qw(@ISA);
use strict;

use FreezeThaw qw(freeze thaw);

# Object preamble - inherits from Bio::Root::Object;

use Bio::EnsEMBL::Pipeline::DB::JobI;
use Bio::EnsEMBL::Pipeline::LSFJob;
use Bio::EnsEMBL::Pipeline::Analysis;
use Bio::EnsEMBL::Pipeline::Status;

@ISA = qw(Bio::EnsEMBL::Pipeline::DB::JobI Bio::Root::Object);

sub _initialize {
    my ($self,@args) = @_;

    my $make = $self->SUPER::_initialize;
    my ($dbobj,$id,$lsfid,$input_id,$analysis,$queue,$create,$stdout,$stderr,$input,$output,$status) 
	= $self->_rearrange([qw(DBOBJ
				ID
				LSF_ID
				INPUT_ID
				ANALYSIS
				QUEUE
				CREATE
				STDOUT
				STDERR
				INPUT_OBJECT_FILE
				OUTPUT_FILE
                                STATUS_FILE
				)],@args);

    $id    = -1 unless defined($id);
    $lsfid = -1 unless defined($lsfid);

    $input_id   || $self->throw("Can't create a job object without an input_id");
    $dbobj      || $self->throw("Can't create a job object without a database handle");
    $queue      || $self->throw("Can't create a job object without a queue");
    $analysis   || $self->throw("Can't create a job object without an analysis object");

    $dbobj->isa("Bio::EnsEMBL::Pipeline::DBSQL::Obj") || 
	$self->throw("Database object [$dbobj] is not a Bio::EnsEMBL::Pipeline::DBSQL::Obj");
    $analysis->isa("Bio::EnsEMBL::Pipeline::Analysis") ||
	$self->throw("Analysis object [$analysis] is not a Bio::EnsEMBL::Pipeline::Analysis");

    $self->id         ($id);
    $self->_dbobj     ($dbobj);
    $self->input_id   ($input_id);
    $self->analysis   ($analysis);
    $self->stdout_file($stdout);
    $self->stderr_file($stderr);
    $self->input_object_file($input);
    $self->output_file($output);
    $self->status_file($status);

    my $job = new Bio::EnsEMBL::Pipeline::LSFJob(-queue     => $queue,
						 -exec_host => "__NONE__",
						 -id        => $lsfid);

    $self->_LSFJob($job);

    if ($create == 1) {
	$self->get_id;
    }

    return $make; # success - we hope!
}

=head2 id

  Title   : id
  Usage   : $self->id($id)
  Function: Get/set method for the id of the job itself
            This will usually be generated by the
            back end database the jobs are stored in
  Returns : int
  Args    : int

=cut


sub id {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_id} = $arg;
    }
    return $self->{_id};

}


=head2 get_id

  Title   : get_id
  Usage   : my $newid = $self->get_id
  Function: Creates a new job entry in the database
            and returns the new id.
  Returns : int
  Args    : 

=cut


sub get_id {
    my ($self) = @_;

    my $analysis = $self->_dbobj->write_Analysis($self->analysis);

    $self->analysis($analysis);

    $self->throw("No analysis object defined") unless $self->analysis;
    $self->throw("No analysis id input")       unless defined($self->analysis->id);

    my $query =   "insert into job (id,input_id,analysis,queue) values (NULL,\"" .
				     $self->input_id     . "\",".
				     $self->analysis->id . ",\"" .
				     $self->queue        ."\")";

    my $sth = $self->_dbobj->prepare($query);
    my $res = $sth->execute();

       $sth = $self->_dbobj->prepare("select last_insert_id()");
       $sth->execute;

    my $rowhash = $sth->fetchrow_hashref;
    my $id      = $rowhash->{'last_insert_id()'};

    $self->id($id);

    my $status  = $self->set_status('CREATED');


    return $id;
}

=head2 input_id

  Title   : input_id
  Usage   : $self->input_id($id)
  Function: Get/set method for the id of the input to the job
  Returns : int
  Args    : int

=cut


sub input_id {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_input_id} = $arg;
    }
    return $self->{_input_id};
}

=head2 analysis

  Title   : analysis
  Usage   : $self->analysis($anal);
  Function: Get/set method for the analysis object of the job
  Returns : Bio::EnsEMBL::Pipeline::Analysis
  Args    : bio::EnsEMBL::Pipeline::Analysis

=cut


sub analysis {
    my ($self,$arg) = @_;
    if (defined($arg)) {
	$self->throw("[$arg] is not a Bio::EnsEMBL::Pipeline::Analysis object" ) unless
	    $arg->isa("Bio::EnsEMBL::Pipeline::Analysis");

	$self->{_analysis} = $arg;
    }
    return $self->{_analysis};

}



sub write_object_file {
    my ($self,$arg) = @_;

    $self->throw("No input object file defined") unless defined($self->input_object_file);

    if (defined($arg)) {
	my $str = FreezeThaw::freeze($arg);
	open(OUT,">" . $self->input_object_file) || $self->throw("Couldn't open object file " . $self->input_object_file);
	print(OUT $str);
	close(OUT);
    }
}

=head2 LSF_id

  Title   : LSF_id
  Usage   : $self->LSF_id($id)
  Function: Get/set method for the LSF id of the job
  Returns : int
  Args    : int

=cut


sub LSF_id {
    my ($self,$arg) = @_;

    return $self->_LSFJob->id($arg);
}

=head2 queue

  Title   : queue
  Usage   : $self->queue
  Function: Get/set method for the LSF queue name
  Returns : String
  Args    : String

=cut

sub queue {
    my ($self,$arg) = @_;
    
    return $self->_LSFJob->queue($arg);
}


=head2 machine

  Title   : machine
  Usage   : $self->machine($machine)
  Function: Get/set method for the machine the job is running on
  Returns : string
  Args    : string

=cut

sub machine {
    my ($self,$arg) = @_;

    return $self->_LSFJob->exec_host($arg);

}

=head2 submit

  Title   : submit
  Usage   : $self->submit
  Function: Submits the job to the specified LSF queue
  Returns : 
  Args    : 

=cut

sub submit {
    my ($self,$obj) = @_;

    my $tmpdb = $obj->_dbobj;
    $obj->disconnect;

    $self->write_object_file($obj);
    $obj->_dbobj($tmpdb);
    my $status = $self->set_status("WRITTEN_OBJECT_FILE");
    
    my $cmd = "bsub -q " . $self->queue;

    $cmd .= " -o " . $self->stdout_file . " -e " . $self->stderr_file;
    
    $cmd .= " \"/nfs/disk100/humpub/michele/runner  -object " . $self->input_object_file . " " . 
	                                           "-output " . $self->output_file       . "\"";

    print STDERR "Command is $cmd\n";

    $self->_LSFJob->submit($cmd);

    if ($self->LSF_id != -1) {
	$self->store($obj);
	my $status = $self->set_status("SUBMITTED");
	print STDERR "Submitted job number " . $self->LSF_id . " to queue " . $self->queue . "\n";
	return $status;
    } else {
	$self->throw("Couldn't submit job " . $self->id . " to queue " . $self->queue);
    }
    $obj->_dbobj($tmpdb);
}

=head2 store

  Title   : store
  Usage   : $self->store
  Function: Stores the object as a string in the database
  Returns : Bio::EnsEMBL::Pipeline::Status
  Args    : none

=cut

sub store {
    my ($self,$obj) = @_;


    $self->throw("Not connected to database") unless defined($obj->_dbobj);
    
    my $tmpdb = $obj->_dbobj;
    $obj->disconnect;
    
    my ($jobstr) = FreezeThaw::freeze($obj);
    
    my $query = ("replace into job(id,input_id,analysis,LSF_id,machine,object,queue," .
		 "input_object_file,stdout_file,stderr_file,output_file,status_file) " .
		 "values( " . $obj->id .   ",\"" .
		 $obj->input_id        .   "\"," .
		 $obj->analysis->id    .   "," .
		 $obj->LSF_id          .   ",\"" .
		 $obj->machine         .   "\",\"".
		 $jobstr               .   "\",\"".
		 $obj->queue           .   "\",\"" .
		 $obj->input_object_file . "\",\"".
		 $obj->stdout_file     .   "\",\"".
		 $obj->stderr_file     .   "\",\"" .
		 $obj->output_file     .   "\",\"" .
		 $obj->status_file     .   "\")");
    
    my $sth = $tmpdb->prepare($query);
    my $res = $sth->execute();
    
    $obj->_dbobj($tmpdb);
    
}


=head2 submission_checks

  Title   : submission_checks
  Usage   : $self->submission_checks
  Function: After submission to the LSF queue when 
            the wrapper script is run - these are
            the checks to run (on binaries,databases etc)
            before the job is run.
  Returns : String
  Args    : None

=cut

sub submission_checks {
    my ($self) = @_;

    $self->throw("Method submission_checks not implemented");

}

=head2 set_status

  Title   : set_status
  Usage   : my $status = $job->set_status
  Function: Sets the job status
  Returns : nothing
  Args    : Bio::EnsEMBL::Pipeline::Status

=cut

sub set_status {
    my ($self,$arg) = @_;

    $self->throw("No status input" ) unless defined($arg);

    
    if (!(defined($self->_dbobj))) {
	$self->warn("No database connection.  Can't set status to $arg");
	return;
    }

    my $status;

    eval {	
	my $sth = $self->_dbobj->prepare("insert into jobstatus(id,status,time) values (" .
					 $self->id . ",\"" .
					 $arg      . "\"," .
					 "now())");
	my $res = $sth->execute();

	$sth = $self->_dbobj->prepare("replace into current_status(id,status) values (" .
				      $self->id . ",\"" .
				      $arg      . "\")");

	$res = $sth->execute();
	
	$sth = $self->_dbobj->prepare("select time from jobstatus where id = " . $self->id . 
				      " and status = \""                       . $arg      . "\"");
	
	$res = $sth->execute();
	
	my $rowhash = $sth->fetchrow_hashref();
	my $time    = $rowhash->{'time'};
	
	
	$status = new Bio::EnsEMBL::Pipeline::Status(-jobid   => $self->id,
						     -status  => $arg,
						     -created => $time,
						     );
	
	$self->current_status($status);
	
	print("Status for job [" . $self->id . "] set to " . $status->status . "\n");
    };

    if ($@) {
	$self->warn("Error setting status to $arg");
    } else {
	return $status;
    }
}


=head2 current_status

  Title   : current_status
  Usage   : my $status = $job->current_status
  Function: Get/set method for the current status
  Returns : Bio::EnsEMBL::Pipeline::Status
  Args    : Bio::EnsEMBL::Pipeline::Status

=cut

sub current_status {
    my ($self,$arg) = @_;
    
    if (defined($arg)) {
	$self->throw("[$arg] is not a Bio::EnsEMBL::Pipeline::Status object") unless
	    $arg->isa("Bio::EnsEMBL::Pipeline::Status");
	$self->{_status} = $arg;
    }
    else {
	$self->throw("Can't get status if id not defined") unless defined($self->id);
	my $id =$self->id;
	my $sth = $self->_dbobj->prepare("select status from current_status where id=$id");
	my $res = $sth->execute();
	my $status;
	while (my  $rowhash = $sth->fetchrow_hashref() ) {
	    $status    = $rowhash->{'status'};
	}
	my $sth = $self->_dbobj->prepare("select now()");
	my $res = $sth->execute();
	my $time;
	while (my  $rowhash = $sth->fetchrow_hashref() ) {
	    $time    = $rowhash->{'now()'};
	}
	my $statusobj = new Bio::EnsEMBL::Pipeline::Status(-jobid   => $self->id,
							   -status  => $status,
							   -created => $time,
							   );
	
	$self->{_status} = $statusobj;
    }
    return $self->{_status};
}

=head2 get_all_status

  Title   : get_all_status
  Usage   : my @status = $job->get_all_status
  Function: Get all status objects associated with this job
  Returns : @Bio::EnsEMBL::Pipeline::Status
  Args    : @Bio::EnsEMBL::Pipeline::Status

=cut

sub get_all_status {
    my ($self) = @_;

    $self->throw("Can't get status if id not defined") unless defined($self->id);

    my $sth = $self->_dbobj->prepare("select id,status,time from  jobstatus " . 
				     "where id = \"" . $self->id . "\" order by time desc");

    my $res = $sth->execute();

    my @status;

    while (my  $rowhash = $sth->fetchrow_hashref() ) {
	my $time      = $rowhash->{'time'};
	my $status    = $rowhash->{'status'};
	
	my $statusobj = new Bio::EnsEMBL::Pipeline::Status(-jobid   => $self->id,
							   -status  => $status,
							   -created => $time,
							   );
	
	
	push(@status,$statusobj);
	
    }

    return @status;
}


=head2 _dbobj

  Title   : _dbobj
  Usage   : my $db = $self->_dbobj
  Function: Get/set method for the database handle
  Returns : @Bio::EnsEMBL::Pipeline::DBSQL::Obj
  Args    : @Bio::EnsEMBL::Pipeline::DBSQL::Obj,none

=cut

sub _dbobj {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->throw("[$arg] is not a Bio::EnsEMBL::Pipeline::DBSQL::Obj") unless 
	    $arg->isa("Bio::EnsEMBL::Pipeline::DBSQL::Obj");

	$self->{_dbobj} = $arg;
    }
    return $self->{_dbobj};
}


sub make_filenames {
    my ($self) = @_;

    my $input_object_file = $self->get_file("job","obj");
    my $stdout_file       = $self->get_file("job","out");
    my $stderr_file       = $self->get_file("job","err");
    my $output_file       = $self->get_file("job","dat");
    my $status_file       = $self->get_file("job","status");

    $self->input_object_file($input_object_file);
    $self->stdout_file      ($stdout_file);
    $self->stderr_file      ($stderr_file);
    $self->output_file      ($output_file);
    $self->status_file      ($status_file);

}


sub get_file {
    my ($self,$stub,$ext) = @_;

    my $dir = "/nfs/disk100/humpub/humpub3/michele/out/";

    # Should check disk space here.

    my $rand  = int(rand(10000));
    my $file  = $dir . $stub . "." . $rand . "." . $ext;
    my $count = 0;

    while (-e $file && $count < 10000) {
	$rand = int(rand(10000));
	$file = $dir . $stub . "." . $rand . "." . $ext;
	$count++;
    }

    if ($count == 10000) {
	$self->throw("10000 files in directory. Can't make a new file");
    } else {
	return $file;
    }
}



=head2 stdout_file

  Title   : stdout_file
  Usage   : my $file = $self->stdout_file
  Function: Get/set method for stdout.
  Returns : string
  Args    : string

=cut

sub stdout_file {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_stdout_file} = $arg;
    }
    return $self->{_stdout_file};
}

=head2 stderr_file

  Title   : stderr_file
  Usage   : my $file = $self->stderr_file
  Function: Get/set method for stderr.
  Returns : string
  Args    : string

=cut

sub stderr_file {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_stderr_file} = $arg;
    }
    return $self->{_stderr_file};
}

=head2 status_file

  Title   : status_file
  Usage   : my $file = $self->status_file
  Function: Get/set method for status
  Returns : string
  Args    : string

=cut

sub status_file {
    my ($self,$arg) = @_;

    if (defined($arg)) {
        $self->{_status_file} = $arg;
    }
    return $self->{_status_file};
}

=head2 output_file

  Title   : output_file
  Usage   : my $file = $self->output_file
  Function: Get/set method for output
  Returns : string
  Args    : string

=cut

sub output_file {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_output_file} = $arg;
    }
    return $self->{_output_file};
}


=head2 input_object_file

  Title   : intput_object_file
  Usage   : my $file = $self->input_object_file
  Function: Get/set method for the input object file
  Returns : string
  Args    : string

=cut

sub input_object_file {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{_input_object_file} = $arg;
    }
    return $self->{_input_object_file};
}
    

=head2 _LSFJob

  Title   : _LSFJob
  Usage   : my $job = $self->_LSFJob
  Function: Get/set method for the LSF job object
  Returns : Bio::EnsEMBL::Pipeline::LSFJob
  Args    : Bio::EnsEMBL::Pipeline::LSFJob

=cut

sub _LSFJob {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	if ($arg->isa("Bio::EnsEMBL::Pipeline::LSFJob")) {
	    $self->{_LSFJob} = $arg;
	} else {
	    $self->throw("[$arg] is not a Bio::EnsEMBL::Pipeline::LSFJob");
	}
    }

    return $self->{_LSFJob};
}


sub print {
    my ($self) = @_;
    print("\n");
    $self->print_var("ID"               , $self->id                     );
    $self->print_var("Input_id"         , $self->input_id               );
    $self->print_var("Machine"          , $self->machine                );
    $self->print_var("LSF_id"           , $self->LSF_id                 );
    $self->print_var("Machine"          , $self->machine                );
    $self->print_var("Queue"            , $self->queue                  );
    $self->print_var("Stdout"           , $self->stdout_file            ); 
    $self->print_var("Stderr"           , $self->stderr_file            ); 
    $self->print_var("Object"           , $self->input_object_file      ); 
    $self->print_var("Output"           , $self->output_file            ); 
    $self->print_var("Status"           , $self->status_file            ); 
    $self->print_var("Analysis_id"      , $self->analysis->id           );
    $self->print_var("Created"          , $self->analysis->created      );
    $self->print_var("Program"          , $self->analysis->program      );
    $self->print_var("Program_version"  , $self->analysis->program_version );
    $self->print_var("Program_file"     , $self->analysis->program_file ); 
    $self->print_var("Database"         , $self->analysis->db           );
    $self->print_var("Database_version" , $self->analysis->db_version   );
    $self->print_var("Database_file"    , $self->analysis->db_file      ); 
    $self->print_var("Module"           , $self->analysis->module       );
    $self->print_var("Module_version"   , $self->analysis->module_version );
    $self->print_var("Parameters"       , $self->analysis->parameters   );
    
    my @status = $self->get_all_status;
    print("\n");
    foreach my $status (@status) {
	$self->print_var("  - Status" ,$status->status . "\t" . $status->created);
    }

}

sub print_var {
    my ($self,$str,$var) = @_;
    printf("%20s %20s\n",$str,$var);
}

sub disconnect {
    my ($self) = @_;

    $self->{_dbobj} = undef;
}
;






