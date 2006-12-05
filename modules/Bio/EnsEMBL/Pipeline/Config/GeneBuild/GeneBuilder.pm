# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Pipeline::Config::GeneBuild::GeneBuilder - imports global variables used by EnsEMBL gene building

=head1 SYNOPSIS
    use Bio::EnsEMBL::Pipeline::Config::GeneBuild::GeneBuilder;
    use Bio::EnsEMBL::Pipeline::Config::GeneBuild::GeneBuilder qw(  );

=head1 DESCRIPTION

GeneBuilder is a pure ripoff of humConf written by James Gilbert.

humConf is based upon ideas from the standard perl Env environment
module.

It imports and sets a number of standard global variables into the
calling package, which are used in many scripts in the human sequence
analysis system.  The variables are first decalared using "use vars",
so that it can be used when "use strict" is in use in the calling
script.  Without arguments all the standard variables are set, and
with a list, only those variables whose names are provided are set.
The module will die if a variable which doesn\'t appear in its
C<%GeneBuilder> hash is asked to be set.

The variables can also be references to arrays or hashes.

Edit C<%GeneBuilder> to add or alter variables.

All the variables are in capitals, so that they resemble environment
variables.

=head1 CONTACT

=cut


package Bio::EnsEMBL::Pipeline::Config::GeneBuild::GeneBuilder;

use strict;
use vars qw( %GeneBuilder );

# Hash containing config info
%GeneBuilder = (

		GB_FINAL_GENETYPE           => 'ensembl', 

                # other gene-types which have to be combined / fetched (in GB_COMB_DBNAME)
                # make sure you don't use GB_GENEWISE_COMBINED_GENETYPE (Combined.pm), 
                # GB_TARGETTED_GW_GENETYPE or  other genetypes mentioned in other configs
                # otherwise genes will be fetched twice 
                #
	        GB_MISC_OTHER_INPUT_GENETYPES => [''], 

		# parameters for use of genscan predictions in final build		
		GB_USE_ABINITIO            => '0',
		GB_ABINITIO_TYPE           => 'ab_initio',
		GB_ABINITIO_SUPPORTED_TYPE => 'ab_initio_supported',
		GB_ABINITIO_PROTEIN_EVIDENCE => ['Swall'],
		GB_ABINITIO_DNA_EVIDENCE     => ['Vertrna', 'Unigene'],

                GB_ABINITIO_LOGIC_NAME => 'Genscan', 
                #this must be a single logic_name, it only has to be defined if you
                #have more than one type in the prediction transcript table as this
                #breaks the PredictionGenebuilder if multiple sets are passed in
		GB_MIN_GENSCAN_EXONS        => 4,
		GB_GENSCAN_MAX_INTRON       => 15000,

                # If you want to confirm prediction transcripts with pfam. 
		# This option is currently only used for anopheles. 
		# Use with caution as the result will be drastically different 
		# than what you get with the default option.
		GB_CONFIRM_PFAM             => '0',

		# lower bound in the 'base align features' retrieved in the genebuilder
		GB_MIN_FEATURE_SCORE        => 50,
		GB_MIN_FEATURE_LENGTH       => 15,

	        # are we running on slices or RawContigs? This may be obsolete
		GB_VCONTIG                  => 1,
		
		# maximum number of transcripts per gene
		GB_MAX_TRANSCRIPTS_PER_GENE => 10,
		
		# Other parameters of the GeneBuild, also used in the post genebuild checks
		
		# introns smaller than this could be real due to framshifts
		GB_MINSHORTINTRONLEN    => 7, 
		
		# introns between smaller than this is considered too short
		GB_MAXSHORTINTRONLEN    => 15, 
		
		#
		# the rest of these don't seem to be used any more
		#

		# introns longer than this are too long
		GB_MINLONGINTRONLEN     => 200000, 
		
		# exons smaller than this could be real due to framshifts
		GB_MINSHORTEXONLEN      => 3, 
		
		# exons shorter than this are too short
		GB_MAXSHORTEXONLEN      => 10, 
		
		# exons longer than this are probably too long
		GB_MINLONGEXONLEN       => 5000, 
		
		GB_MINTRANSLATIONLEN    => 10, 

		GB_MAX_EXONSTRANSCRIPT  => 150, 

		GB_MAXTRANSCRIPTS       => 10, 
		GB_MAXGENELEN           => 2_000_000, 

		GB_IGNOREWARNINGS       => 1, 	    

	       );

sub import {
  my ($callpack) = caller(0); # Name of the calling package
  my $pack = shift; # Need to move package off @_
  
  # Get list of variables supplied, or else
  # all of GeneBuilder:
  my @vars = @_ ? @_ : keys( %GeneBuilder );
  return unless @vars;
  
  # Predeclare global variables in calling package
  eval "package $callpack; use vars qw("
    . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;


    foreach (@vars) {
	if ( defined $GeneBuilder{ $_ } ) {
            no strict 'refs';
	    # Exporter does a similar job to the following
	    # statement, but for function names, not
	    # scalar variables:
	    *{"${callpack}::$_"} = \$GeneBuilder{ $_ };
	} else {
	    die "Error: GeneBuilder: $_ not known\n";
	}
    }
}

1;
