# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Pipeline::Config::GeneBuild::UTR_Builder - imports global variables used by EnsEMBL gene building

=head1 SYNOPSIS
    use Bio::EnsEMBL::Pipeline::Config::GeneBuild::UTR_Builder;
    use Bio::EnsEMBL::Pipeline::Config::GeneBuild::UTR_Builder qw(  );

=head1 DESCRIPTION

UTR_Builder is a pure ripoff of humConf written by James Gilbert.

humConf is based upon ideas from the standard perl Env environment
module.

It imports and sets a number of standard global variables into the
calling package, which are used in many scripts in the human sequence
analysis system.  The variables are first decalared using "use vars",
so that it can be used when "use strict" is in use in the calling
script.  Without arguments all the standard variables are set, and
with a list, only those variables whose names are provided are set.
The module will die if a variable which doesn\'t appear in its
C<%UTR_Builder> hash is asked to be set.

The variables can also be references to arrays or hashes.

Edit C<%UTR_Builder> to add or alter variables.

All the variables are in capitals, so that they resemble environment
variables.

=head1 CONTACT

=cut


package Bio::EnsEMBL::Pipeline::Config::GeneBuild::UTR_Builder;

use strict;
use vars qw( %UTR_Builder );

# Hash containing config info
%UTR_Builder = (


	     # gene type for Combine_Genewises_and_E2Gs
	     GB_GENEWISE_COMBINED_GENETYPE           => 'UTR',

	     GB_BLESSED_COMBINED_GENETYPE           => 'BlessedUTR',

	     # gene type for cDNAs aligned with exonerate & est2genome
	     GB_cDNA_GENETYPE               => 'cdna_exonerate',

	     # gene type for ESTs aligned with exonerate & est2genome
	     GB_EST_GENETYPE               => 'est_exonerate',
	     
	     # don't allow introns longer than this - transcripts are split
	     GB_COMBINED_MAX_INTRON         => 10000,	    

	     # for est2genome runnabledb (This should probably be in ESTConf.pm)
	     GB_EST_DATABASES => [
                                  # fill in one complete hash for each database from which blast 
                                  # features are to be retrieved
                                  { 
				   'type'       => '', # logic name
                                   'threshold'  => '', # threshold
                                   'index'      => '', # '/full/path/to/index_name'
                                  },
				 ],
	     
	     GB_EST_GENETYPE => 'est2genome',

	     # add other non-generic gene-types
	     # format: ['exonerate_genes', 'other_great_genes']
	     OTHER_GENETYPES => [],
	     
             # GB_UTR_BUILD_LEVEL specifies how the CDS and cDNA/EST data are to be combined
             # Default is not to build UTRs
             # 1 : Basic cDNA build; uses cDNA alignments and
             # genewises, requires matching only at genewise terminal
             # exons (old approach)
             # 2 : Strict cDNA build(recommended); uses cDNA
             # alignments and genewises. Two step matching process,
             # first requiring matching of internal genewise
             # structures and cDNA alignments, then attempting to
             # match unused cDNAs and genewises looking only at
             # terminal genewise exons
             # 3 : EST build; uses EST alignments and genewises. ESTs
             # are clustered, must have 2 (?3) ESTs with matching
             # structures to be able to build UTR. Internal structures
             # must match over the length of the EST can modify
             # unblessed UTRs only

             GB_UTR_BUILD_LEVEL => 1,

	     #GB_UTR_BUILD_LEVEL 3 can use ditags to filter ESTs
             # format: ['ditagtype_1', 'ditagtype_2']
	     DITAG_LOGIC_NAME   => [],

	   );

sub import {
  my ($callpack) = caller(0); # Name of the calling package
  my $pack = shift; # Need to move package off @_
  
  # Get list of variables supplied, or else
  # all of UTR_Builder:
  my @vars = @_ ? @_ : keys( %UTR_Builder );
  return unless @vars;
  
  # Predeclare global variables in calling package
  eval "package $callpack; use vars qw("
    . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;


    foreach (@vars) {
	if ( defined $UTR_Builder{ $_ } ) {
            no strict 'refs';
	    # Exporter does a similar job to the following
	    # statement, but for function names, not
	    # scalar variables:
	    *{"${callpack}::$_"} = \$UTR_Builder{ $_ };
	} else {
	    die "Error: UTR_Builder: $_ not known\n";
	}
    }
}

1;
