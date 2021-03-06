#!/usr/bin/perl
#
#Configuration for ecweb
# perhaps a config file to be read and parsed ...
#
package ecwebconsts;

use strict;
use Env qw ($HOME);
#use Relay::Common qw ($RELAY_DATA);
use Exporter ();
use vars qw( $ECBASE $VERSION $ECTEMPDIR $ECSCRIPT $SOLRURL @EXPORT); 
	
$VERSION   = '1.0_03';
our @ISA   = qw(Exporter);
@EXPORT    = qw($ECBASE $ECSCRIPT $ECTEMPDIR $SOLRURL);

# change if nedded
$ECTEMPDIR = "/data/temp/ec";
# fix this 
#$ECSCRIPT = "${HOME}/relay-analysis/perl/ec.d/ec.pl";
$ECSCRIPT = "${HOME}/gitprojects//RelayEntityCounts/ec.pl";
# this is hardwired for a partiuclar instance of a webapp, but could change (e.g. localhost)
$SOLRURL = "http://localhost:8983/solr/relaycontent/";
#$ATTIVIOURL = "http://localhost:17001";
# ecbase - base url which should reflect the environment (proxied by apache)
$ECBASE = "http://localhost:3000/ec";
#$ECBASE = "http://localhost:3000";

1;
