# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Pipeline::Config::GeneBuild::Combined - imports global variables used by EnsEMBL gene building

=head1 SYNOPSIS
    use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Combined;
    use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Combined qw(  );

=head1 DESCRIPTION

Combined is a pure ripoff of humConf written by James Gilbert.

humConf is based upon ideas from the standard perl Env environment
module.

It imports and sets a number of standard global variables into the
calling package, which are used in many scripts in the human sequence
analysis system.  The variables are first decalared using "use vars",
so that it can be used when "use strict" is in use in the calling
script.  Without arguments all the standard variables are set, and
with a list, only those variables whose names are provided are set.
The module will die if a variable which doesn\'t appear in its
C<%Combined> hash is asked to be set.

The variables can also be references to arrays or hashes.

Edit C<%Combined> to add or alter variables.

All the variables are in capitals, so that they resemble environment
variables.

=head1 CONTACT

=cut


package Bio::EnsEMBL::Pipeline::Config::GeneBuild::Combined;

use strict;
use vars qw( %Combined );

# Hash containing config info
%Combined = (


	     # gene type for Combine_Genewises_and_E2Gs
	     GB_GENEWISE_COMBINED_GENETYPE           => 'UTR',

	     GB_BLESSED_COMBINED_GENETYPE           => 'BlessedUTR',

	     # gene type for genes built from cDNAs with exonerate & est2genome
             # you may pass one single value as well as an arrayref ['type_1','type_2'] , 
	     GB_cDNA_GENETYPE               => 'exonerate_e2g',
	     
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
	     

	   );

sub import {
  my ($callpack) = caller(0); # Name of the calling package
  my $pack = shift; # Need to move package off @_
  
  # Get list of variables supplied, or else
  # all of Combined:
  my @vars = @_ ? @_ : keys( %Combined );
  return unless @vars;
  
  # Predeclare global variables in calling package
  eval "package $callpack; use vars qw("
    . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;


    foreach (@vars) {
	if ( defined $Combined{ $_ } ) {
            no strict 'refs';
	    # Exporter does a similar job to the following
	    # statement, but for function names, not
	    # scalar variables:
	    *{"${callpack}::$_"} = \$Combined{ $_ };
	} else {
	    die "Error: Combined: $_ not known\n";
	}
    }
}

1;
