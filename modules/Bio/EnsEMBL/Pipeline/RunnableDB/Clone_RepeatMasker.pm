#
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

Bio::EnsEMBL::Pipeline::RunnableDB::Clone_RepeatMasker

=head1 SYNOPSIS

my $db      = Bio::EnsEMBL::DBLoader->new($locator);
my $repmask = Bio::EnsEMBL::Pipeline::RunnableDB::Clone_RepeatMasker->new ( 
                                                    -db      => $db,
			                                        -input_id   => $input_id
                                                    -analysis   => $analysis );
$repmask->fetch_input();
$repmask->run();
$repmask->output();
$repmask->write_output(); #writes to DB

=head1 DESCRIPTION

This object wraps Bio::EnsEMBL::Pipeline::Runnable::RepeatMasker to add
functionality to read and write to databases. 
This object takes clone ids, Bio::EnsEMBL::Pipeline::RunnabdleDB::RepeatMasker 
acts on contigs. 
The appropriate Bio::EnsEMBL::Pipeline::Analysis object must be passed for
extraction of appropriate parameters. A Bio::EnsEMBL::Pipeline::DBSQL::Obj is
required for databse access.

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Pipeline::RunnableDB::Clone_RepeatMasker;

use strict;
use Bio::EnsEMBL::Pipeline::RunnableDB::RepeatMasker;

use vars qw(@ISA);
@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableDB::RepeatMasker);

=head2 new

    Title   :   new
    Usage   :   $self->new(-DB       => $db
                           -INPUT_ID    => $id
                           -ANALYSIS    => $analysis);
                           
    Function:   creates a Bio::EnsEMBL::Pipeline::RunnableDB::RepeatMasker object
    Returns :   A Bio::EnsEMBL::Pipeline::RunnableDB::RepeatMasker object
    Args    :        -db:     A Bio::EnsEMBL::DB::Obj, 
                input_id:   Contig input id , 
                -analysis:  A Bio::EnsEMBL::Pipeline::Analysis

=cut

sub new {
    my ($class, @args) = @_;
    my $self = $class->SUPER::new(@args);
    
    $self->{'_fplist'}      = [];
    $self->{'_runnable'}    = [];
    
    $self->throw("Analysis object required") unless ($self->analysis);    
    return $self;
}

=head2 fetch_input

    Title   :   fetch_input
    Usage   :   $self->fetch_input
    Function:   Fetches input data for repeatmasker from the database
    Returns :   none
    Args    :   none

=cut

sub fetch_input {
    my( $self) = @_;
    
    $self->throw("No input id") unless defined($self->input_id);

#    print STDERR "Input id " . $self->input_id . "\n";
#    print STDERR "Db " . $self->db . "\n";
    
    my $cloneid     = $self->input_id;
    my $clone       = $self->db->get_CloneAdaptor->fetch_by_accession($cloneid);
    my ($contig) = $clone->get_all_Contigs();
    
foreach my $contig  ($clone->get_all_Contigs())
    {       
#      my $genseq = $contig->primary_seq() or $self->throw("Unable to fetch contig");
      $self->runnable($contig);
    }
}

#get/set for runnable and args

sub runnable {
    my ($self, $genseq) = @_;
    if ($genseq)
    {
	my $repeatmask = Bio::EnsEMBL::Pipeline::Runnable::RepeatMasker->new (
									      -query    => $genseq,
									      );
	
	push (@{$self->{'_runnable'}}, $repeatmask);

    }
    return @{$self->{'_runnable'}};
}

=head2 run

    Title   :   run
    Usage   :   $self->run();
    Function:   Runs Bio::EnsEMBL::Pipeline::Runnable::RepeatMasker->run()
    Returns :   none
    Args    :   none

=cut

sub run {
    my ($self) = @_;
    $self->throw("Runnable modules not set") unless ($self->runnable());
    foreach my $runnable ($self->runnable)
    {
        $runnable->run();
    }
}

=head2 output

    Title   :   output
    Usage   :   $self->output();
    Function:   Runs Bio::EnsEMBL::Pipeline::Runnable::RepeatMasker->output()
    Returns :   An array of Bio::EnsEMBL::Repeat objects (FeaturePairs)
    Args    :   none

=cut

sub output {
    my ($self) = @_;
    
    my @output;
    foreach my $runnable ($self->runnable)
    {
        push (@output, $runnable->output());
    }
    return @output;
}

=head2 fetch_output

    Title   :   fetch_output
    Usage   :   $self->fetch_output($file_name);
    Function:   Fetchs output data from a frozen perl object
                stored in file $file_name
    Returns :   array of repeats (with start and end)
    Args    :   none

=cut

=head2 write_output

    Title   :   write_output
    Usage   :   $self->write_output
    Function:   Writes output data to db
    Returns :   array of repeats (with start and end)
    Args    :   none

=cut

sub write_output {
    my($self) = @_;
    
    $self->throw("fetch_input must be called before write_output\n") 
        unless ($self->runnable);

    my $db=$self->db();
    foreach my $runnable ($self->runnable)
    {
        my $contig;
        my @repeats = $runnable->output();
        eval 
        {
	    $contig = $db->get_RawContigAdaptor()->fetch_by_name($runnable->query->display_id);
        };
        if ($@) 
        {
	        print STDERR "Contig not found, skipping writing output to db\n" . $@ . "\n";
        }
        elsif (@repeats) 
        {
	    foreach my $repeat (@repeats)
            {
		$repeat->analysis($self->analysis);
            }
		my $feat_adp = $db->get_RepeatFeatureAdaptor;
	        $feat_adp->store($contig->dbID, @repeats);
        }
        return 1;
    } 
}

1;
