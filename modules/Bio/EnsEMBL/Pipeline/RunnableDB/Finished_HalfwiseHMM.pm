#
#
# Cared for by EnsEMBL  <ensembl-dev@ebi.ac.uk>
# Copyright GRL & EBI
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Pipeline::RunnableDB::HalfwiseHMM

=head1 SYNOPSIS

    my $obj = Bio::EnsEMBL::Pipeline::RunnableDB::HalfwiseHMM->new(
					     -db     => $db,
					     -input_id  => $id
                                             );
    $obj->fetch_input
    $obj->run

    my @newfeatures = $obj->output;


=head1 DESCRIPTION

runs HalfwiseHMM runnable and converts it output into genes which can be stored in an ensembl database

=head1 CONTACT

lec@sanger.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::EnsEMBL::Pipeline::RunnableDB::Finished_HalfwiseHMM;

use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::EnsEMBL::Root;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Pipeline::Runnable::Finished_HalfwiseHMM;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Similarity qw (
							     GB_SIMILARITY_DATABASES
							    );

use Data::Dumper;

@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableDB);

=head2  new

    Arg      : all those inherited from RunnableDB
    Function : Make a new HalfwiseHMM object defining the above variables
    Exception: thrown if no input id is provided, this is found in RunnableDB
    Caller   : 
    Example  : $runnable = Bio::EnsEMBL::Pipeline::RunnableDB::HalfwiseHMM new->(-db => $db
										 -INPUT_ID => $id
										 -ANALYSIS => $analysis);

=cut


sub new {
    my ($new,@args) = @_;
    my $self = $new->SUPER::new(@args);    
           
    # db, input_id, seqfetcher, and analysis objects are all set in
    # in superclass constructor (RunnableDB.pm)
    my ($type, $threshold) = $self->_rearrange([qw(TYPE THRESHOLD)], @args);
    $self->{'_fplist'} = []; #create key to an array of feature pairs

    return $self;
}

sub type {
  my ($self,$type) = @_;

  if (defined($type)) {
    $self->{_type} = $type;
  }
  return $self->{_type};
}

sub threshold {
  my ($self,$threshold) = @_;

  if (defined($threshold)) {
    $self->{_threshold} = $threshold;
  }
  return $self->{_threshold};
}


=head2  fetch_input

    Arg      : none
    Function : fetches the repeatmasked sequence and the swall features for the contig being run on and creates the HalfwiseHMM Runnable
    Exception: throws if no input_id has been provided
    Caller   : 
    Example  : 

=cut

sub fetch_input {
  my( $self) = @_;
  #print "running fetch input\n"; 
  my %ests;
  my @estseqs;
  $self->throw("No input id") unless defined($self->input_id);
  
  
  my $contig    = $self->db->get_RawContigAdaptor->fetch_by_name($self->input_id);
  #print "got contig\n";
  my $genseq   = $contig->get_repeatmasked_seq;
  #print "got dnaseq\n";
  
  #print $features[0]."\n";
  #print "got data\n";
  
  my $alignAdaptor = $self->db->get_ProteinAlignFeatureAdaptor();
  
  foreach my $database(@{$GB_SIMILARITY_DATABASES}){
     my $fps = [];
    my $features = $alignAdaptor->fetch_all_by_RawContig_and_pid($contig, 
					       $database->{'threshold'}, 
					       $database->{'type'});
  
    print STDERR "Number of features matching threshold $database->{'threshold'} = " . scalar(@$features) . "\n";

  
    foreach my $f (@$features) {
      if (UNIVERSAL::isa($f,"Bio::EnsEMBL::FeaturePair") && defined($f->hseqname)) {
	push(@$fps, $f);
      }
    }
    #print "got".scalar(@$fps)." feature pairs\n";
    #print STDERR "have ".$genseq."\n";
    my $runnable =
        Bio::EnsEMBL::Pipeline::Runnable::Finished_HalfwiseHMM->new('-query'    => $genseq,
                                                                    '-features' => $fps,
                                                                    '-pfamdb'   => $self->getPfamDB(),
                                                                    '-options'  => $self->parameters(),
                                                                    '-program'  => $self->analysis->program()
        );
    #print "created HalfwiseHMM Runnable\n";  
    $self->runnable($runnable);
    #print "finshed fetching input\n";
   
  }    

}

=head2

Nasty hack to get a handle to a pfam database, should probably use pfam code

=cut

sub getPfamDB{
    my ($self) = @_;
    unless($self->{'_pfam_db'}){
        my $pfam_db = $self->db->get_meta_value_by_key('pfam_db');        
        $self->{'_pfam_db'} = Bio::EnsEMBL::DBSQL::DBAdaptor->new(%{$self->db->make_hash_from_meta_value($pfam_db)});
    }
    return $self->{'_pfam_db'};
} 
    
=head2  runnable

    Arg      : a Bio::EnsEMBL::Pipeline::RunnableI
    Function : Gets/sets the runnable 
    Exception: throws if argument passed isn't a runnable
    Caller   : 
    Example  :'

=cut    
    

sub runnable {
    my ($self,$arg) = @_;
 
    if(!defined($self->{'_seqfetchers'})) {
      $self->{'_seqfetchers'} = [];
    }
    
    if (defined($arg)) {
      $self->throw("[$arg] is not a Bio::EnsEMBL::Pipeline::RunnableI") unless $arg->isa("Bio::EnsEMBL::Pipeline::RunnableI");
	
      push(@{$self->{_runnable}}, $arg);
    }

    return @{$self->{_runnable}};
}

sub run {
    my ($self) = @_;
 
    foreach my $runnable ($self->runnable) {
      $runnable || $self->throw("Can't run - no runnable object");
      print STDERR "using ".$runnable."\n";
      $runnable->run;
    }
   
   
    $self->_convert_output();
    #print "have run est2genome\n";
}



=head2  output

    Arg      : none
    Function : returns the output from the halfwisehmm runnable
    Exception: none
    Caller   : 
    Example  :

=cut


#sub output {
#    my ($self) = @_;
#    my @out = $self->runnable->output();
#    return @out;
#}
 

=head2  write_output


    Arg      : none
    Function : writes the converted output to the database as genes
    Exception: none
    Caller   : 
    Example  :

=cut

sub write_output {

  my($self) = @_;
  my @times = times;
  print STDERR "started writing @times \n";
  #$self->_convert_output();
  my @genes    = $self->output();
  
  my $db       = $self->db();


  my $gene_adaptor= $self->db->get_GeneAdaptor;

  GENE: foreach my $gene (@genes) {	
    # do a per gene eval...
    eval {
      #print "gene = ".$gene->type()."\n";
      $gene_adaptor->store($gene);
    }; 
    if( $@ ) {
      print STDERR "UNABLE TO WRITE GENE\n\n$@\n\nSkipping this gene\n";
    }
    
  }
  @times = times;
  print STDERR "finished writing @times \n";
  #$self->throw("don't die just yet");
   return 1;
}


=head2  _convert_output

    Arg      : none
    Function : takes the features from the halfwise runnable and runs _make_genes to convert them into Bio::EnsEMBL::Genes with appropriately attached exons and supporting evidence
    Exception: thows if there are no analysis types
    Caller   : 
    Example  :

=cut


sub _convert_output {
  my ($self) = @_;
  #print "converting genes to features\n";
  my @genes;
  my $genetype = 'Halfwise';
  my $anaAdaptor = $self->db->get_AnalysisAdaptor;
  my @analyses = $anaAdaptor->fetch_by_logic_name($genetype);
  my $analysis;
  if(scalar(@analyses) > 1){
    $self->throw("panic! > 1 analysis for $genetype\n");
  }
  elsif(scalar(@analyses) == 1){
    $analysis = $analyses[0];
  }else{
    # make a new analysis object
    $analysis = new Bio::EnsEMBL::Analysis
      (
       -program         => 'genewise',
       -program_version => 1,
       -gff_source      => 'HalfwiseHMM',
       -gff_feature     => 'gene',
       -logic_name      => 'Halfwise',
       -module          => 'HalfwiseHMM',
      );
  }
   # make an array of genes for each runnable
  my @out;
  foreach my $runnable($self->runnable){
    push(@out, $runnable->output);
    $self->pfam_lookup($runnable->pfam_lookup) if $runnable->can('pfam_lookup');
  }
  #print "HalfwiseDB\n";
  #"converting ".scalar(@out)." features to genes\n";
  my @g = $self->_make_genes($genetype, $analysis, \@out);
  push(@genes, @g);
  
 #print STDOUT "genes = @genes\n";
  
    
  if (!defined($self->{_output})) {
    $self->{_output} = [];
  }
  
  push(@{$self->{_output}},@genes);
}

# get/set for lookup multi-valued hash { pfam_id => [pfam_acc, pfam_desc], ... }
# can append multiple to the lookup (see { %{$self->{'_pfam_lookup'}}, %{$hash_ref} })
sub pfam_lookup{
    my ($self, $hash_ref) = @_;
    if(ref($hash_ref) eq 'HASH'){
        $self->{'_pfam_lookup'} ||= {};
        $self->{'_pfam_lookup'}   = { %{$self->{'_pfam_lookup'}}, %{$hash_ref} };
    }
    return $self->{'_pfam_lookup'};
}

=head2  _make_genes

    Arg      : runnable being run and analysis object being used
    Function : converts the seqfeatures outputed by the runnable and actually converts them into Bio::EnsEMBL::Genes
    Exception: none
    Caller   : 
    Example  :

=cut



=head2 make_genes

  Title   :   make_genes
  Usage   :   $self->make_genes
  Function:   makes Bio::EnsEMBL::Genes out of the output from runnables
  Returns :   array of Bio::EnsEMBL::Gene  
  Args    :   $genetype: string
              $analysis_obj: Bio::EnsEMBL::Analysis
              $results: reference to an array of FeaturePairs

=cut

sub _make_genes {
    my ($self, $genetype, $analysis_obj, $results) = @_;
    my $contig =  $self->db->get_RawContigAdaptor->fetch_by_name($self->input_id);
    my @genes;
#   print "genetype = ".$genetype."\n";
    # fetch lookup multi-valued hash { pfam_id => [pfam_acc, pfam_desc], ... }
    my $pfam_lookup = $self->pfam_lookup();
    foreach my $tmp_gene (@$results) {
        my $pfam_id = $tmp_gene->seqname();
        my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id  => $pfam_lookup->{$pfam_id}->[0],
                                               -display_id  => $pfam_id,
                                               -version     => 1,
                                               -release     => 1,
                                               -dbname      => "PFAM",
                                               -description => $pfam_lookup->{$pfam_id}->[1]
                                              );
        $dbentry->status('XREF');
        my $gene       = Bio::EnsEMBL::Gene->new();;
        my $transcript = $self->_make_transcript($tmp_gene, $contig, $genetype, $analysis_obj);
        $gene->type($genetype);
        $gene->analysis($analysis_obj);
        $gene->add_Transcript($transcript);
        $gene->add_DBEntry($dbentry);
	$gene->display_xref($dbentry);
        push (@genes, $gene);
    }
    
    return @genes;
}

=head2 _make_transcript

 Title   : make_transcript
 Usage   : $self->make_transcript($gene, $contig, $genetype)
 Function: makes a Bio::EnsEMBL::Transcript from a SeqFeature representing a gene, 
           with sub_SeqFeatures representing exons.
 Example :
 Returns : Bio::EnsEMBL::Transcript with Bio::EnsEMBL:Exons(with supporting feature 
           data), and a Bio::EnsEMBL::translation
 Args    : $gene: Bio::EnsEMBL::SeqFeatureI, $contig: Bio::EnsEMBL::RawContig,
  $genetype: string, $analysis_obj: Bio::EnsEMBL::Analysis


=cut

sub _make_transcript{
  my ($self, $gene, $contig, $genetype, $analysis_obj) = @_;
  $genetype = 'unspecified' unless defined ($genetype);

  unless ($gene->isa ("Bio::EnsEMBL::SeqFeatureI"))
    {print "$gene must be Bio::EnsEMBL::SeqFeatureI\n";}

  my $transcript   = Bio::EnsEMBL::Transcript->new();
  my $translation  = Bio::EnsEMBL::Translation->new();    
  $transcript->translation($translation);

  my $excount = 1;
  my @exons;
    
  foreach my $exon_pred ($gene->sub_SeqFeature) {
    # make an exon
    #print Dumper $exon_pred;
    my $exon = Bio::EnsEMBL::Exon->new();
    
    $exon->id($contig->dbID);
    $exon->start($exon_pred->start);
    $exon->end  ($exon_pred->end);
    $exon->strand($exon_pred->strand);
    
    $exon->phase($exon_pred->phase || 0);
    $exon->end_phase(0);
    $exon->attach_seq($contig);
    
    # sort out supporting evidence for this exon prediction
    foreach my $subf($exon_pred->sub_SeqFeature){
      $subf->feature1->seqname($contig->dbID);
      $subf->feature1->score(100);
      $subf->feature1->analysis($analysis_obj);
        
      
      $subf->feature2->score(100);
      $subf->feature2->analysis($analysis_obj);
      
      $exon->add_Supporting_Feature($subf);
    }
    
    push(@exons,$exon);
    
    $excount++;
  }
  
  if ($#exons < 0) {
   # printSTDERR "Odd.  No exons found\n";
  } 
  else {
    
    #print STDERR "num exons: " . scalar(@exons) . "\n";

    if ($exons[0]->strand == -1) {
      @exons = sort {$b->start <=> $a->start} @exons;
    } else {
      @exons = sort {$a->start <=> $b->start} @exons;
    }
    
    foreach my $exon (@exons) {
      $transcript->add_Exon($exon);
    }
    
    $translation->start_Exon($exons[0]);
    $translation->end_Exon  ($exons[$#exons]);
    
    if ($exons[0]->phase == 0) {
      $translation->start(1);
    } elsif ($exons[0]->phase == 1) {
      $translation->start(3);
    } elsif ($exons[0]->phase == 2) {
      $translation->start(2);
    }
    
    $translation->end  ($exons[$#exons]->end - $exons[$#exons]->start + 1);
  }
  
  return $transcript;
}



=head2 output

 Title   : output
 Usage   :
 Function: get/set for output array
 Example :
 Returns : array of Bio::EnsEMBL::Gene
 Args    :


=cut

sub output{
   my ($self,@genes) = @_;
  
   if (!defined($self->{'_output'})) {
     $self->{'_output'} = [];
   }
    
   if(defined @genes){
     push(@{$self->{'_output'}},@genes);
   }
   
   return @{$self->{'_output'}};
}

1;