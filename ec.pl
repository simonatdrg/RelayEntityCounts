#!/usr/bin/env perl
#
use strict;
use 5.012;
use Relay::Common qw(logme $RELAY_DATA $RELAY_LOGD);
use FindBin qw($RealBin);
use lib "$RealBin/.";
use Relay::BufferedAttivioQuery;
use ecConfig;
use doSolrQuery;
use Env qw ($HOME);
use Getopt::Long;
use Carp;
use Data::Dumper;
use IO::File;
use ECFilters;

# any signal will be converted into die()
# use sigtrap qw (die );
use vars qw ($AIEerrmsg);

our $ECDIR="$HOME/.ec";
mkdir ($ECDIR)  unless (-d $ECDIR);
my$TEMPDIR = "$ECDIR/temp";
our $opth={};
our $ECVERSION="1.3";

my ($rc, $cfile, $qtype, $docout, $docfh);
$rc = GetOptions($opth, "ids","config=s", "docs:s", "url=s", "test", "res=s", "web=s", "help", "debug");
if (! $rc || $opth->{help}) {
print STDERR  <<EOD;
	$0: Version $ECVERSION
	Options are:
	--help   Print this help
	--config=<configfile> Defaults to standard input
	--docs<=optional_docid_output_file>  If present, don't do counts. If option specified without the output file
	      then write to standard output
    --ids   print only docids matching queries, one per line. Only meaningful if --docs specified. At present, the
	       output file will not be deduped.
	--url=<Attivio URL> (default http://localhost:17001)
	--test   parse config file only, exit status = 0 if OK, 1 if errors 
	--res=<counts results output file> Can't be specified with --docs. If neither --docs
               or --res are specified, then write counts to standard output
	--web=key   Running in web app context (does some under-the-hood stuff, don't
	specify if running from command line !)
EOD
exit(0);
}
if ($opth->{web}) {
	require MongoDB;
	require ECRunner;
}

$cfile = $opth->{config};
$qtype = 'counts';
# output will default to stdout, but for running in web context we need to
# sepcify an output file
#
my $countsfh = *STDOUT;
binmode $countsfh, ":utf8";
if ($opth->{res}) {
	# 
	$countsfh = IO::File->new("> ".$opth->{res});
}

# save filename for doccounts and open file
if (exists $opth->{docs}) {
    if (length $opth->{docs} == 0) {
       $docfh = *STDOUT
	}  else {	
	$docout=$opth->{docs};
	$docfh = IO::File->new("> $docout");
	croak  ("can't create docid file ".$docout) if (! defined $docfh);
	logme("notice", "writing docid output to $docout");
	binmode $docfh, ":utf8";
	}
    $qtype = 'docs';
} 

if (defined $cfile && ! -r ($cfile)) {
	croak "Couldn't find config file $cfile";
}
if (! defined $cfile) {
	$cfile = *STDIN;
}

my $conf = ecConfig->new($cfile, $opth);

my $qry;
my $qs = $conf->{qs};
# my $colorder = $qs->getcols();

while ($qry = $qs->next())
{

#	my $d =Data::Dumper->new([$qry]);
#$Data::Dumper::Indent = 1;
#	print STDERR $d->Dump;
$opth->{url} = "http://awsrelay1:8983/solr";
$opth->{collection} = "relaycontent";
my $qres = doSolrQuery->new($qry, {querytype => $qtype,
								   collection => $opth->{collection},
								   url => $opth->{url}});
# say STDERR $qres->{url};
if ($qtype =~ /counts/) {
	write_long_skinny($conf, $qres, $countsfh);
} elsif ($qtype =~ /docs/) {
    if (defined $opth->{ids}) {
		write_docids($conf,  $qres, $docfh);
	} else {
		write_docinfo($conf, $qres, $docfh);
	}
}	
#	sleep 1;
}
# counts output
# line is: ent value(s)  fulltext(if not *:*) source date(end of quarter) discoveryfacet(if present) count
#
sub write_long_skinny{
	my ($conf, $qres, $countsfh) = @_;
#	my $ = $conf->{qs};
	my @fvals = ();
	# add any static output tags
	foreach my $o (@{$conf->{otags}}){
	 push @fvals,$o;
	}
	
	foreach my $f (@{$qres->{qry}->filters()}) {
		# check if a date range and take last date
		# Solr - modified to strip off millsecs and date math stuff
		my ($sd, $ed)  = $f =~ m!\[(.*)\s+TO\s+(.*)\]!ims ;
		if ($ed) {
			$f = $ed;
			$f =~ s/T.*//;
		} else {
			$f =~ s/^(.*?:)//ms;
			$f =~ s/"//g;
			$f =~ s/[()]//g;
		}
		if ($f =~ /NULL/i) {
				$f='\N';
		}
		
		push @fvals, $f;
	}
	if ($qres->{facets}) {
		if ($qres->{numrows} > 0) {
		# its a single facet...
			my $fc = $qres->{facets}->[0] ;
			# each bucket is a hashref with single k=v (facetname, count)
			my $bucks = $fc->buckets();
			foreach my $bu (@$bucks) {
				my @a = %{$bu};
				say $countsfh join("\t", @fvals), "\t", $a[0],"\t", $a[1];
				}
			} else {
			say $countsfh join("\t", @fvals), "\t","none\t",$qres->{numrows};
		} 
	return;
	}
# just total counts
#	my @fvals = map {  $_ =~  s/^(.*?:)//ms; $_} @{$qres->{qry}->{filters}};
	say $countsfh join("\t", @fvals), "\t",$qres->{numrows};
	return;
}
#
# write just docid
sub write_docids {
	my ($conf, $qres, $docfh) = @_;
    foreach my $rdoc (@{$qres->{docids}}) {
		say $docfh $rdoc->{id};
	}
}
#
# remove ISO 8601 trailing stuff from date field
#
sub reformat_date {
	my ($d) = @_;
	$d =~ s/T.*Z//;
	return $d;
}
#
# doC INFORMATION output
# format is ent values fulltext-if-present source quarterdate docid
sub write_docinfo {
	my ($conf, $qres, $docfh) = @_;
	# precompute the identifying columns
	my @fvals = ();
	my $qry = $qres->{qry};
	my $burstfield = $qry->find_burstfield();
	
	# add any static output tags
	foreach my $o (@{$conf->{otags}}){
	 push @fvals,$o;
	}
	
	foreach my $f (@{$qry->filters()}) {
		# check if a date range and take last date
		my ($sd, $ed)  = $f =~ m!\[(.*)\s+TO\s+(.*)\]!ims ;
		if ($ed) {
			$f = $ed;
			$f =~ s/T.*//;
		} else {
			$f =~ s/^(.*?:)//ms;
			$f =~ s/"//g;
		}
		if ($f =~ /NULL/i) {
				$f='\N';
		}
		
		push @fvals, $f;
	}
	# these are the static cols for this query, computed once
	my $cols = join ("\t", @fvals);
	#
	# now iterate through the result set
	#
	
	foreach my $rdoc (@{$qres->{docids}}) {
		my $splitfieldidx = undef;
		my @thisdoc = ();
		push @thisdoc, $rdoc->{id};
		foreach my $field (@{$qry->fields()}) {
			my $val;
			if ($field =~ /_date/) {
				$val = reformat_date($rdoc->{$field});
			} else {
				$val = $rdoc->{$field};
			}
			push @thisdoc, $val;
			
			if (($field eq $burstfield) && ($val =~ /\|/)) {
				$splitfieldidx = $#{\@thisdoc};  #offset 
			}
			
		}
		# if a field to split, then generate all records
		# based on the split
		#
		if (defined $splitfieldidx) {
			my $f = $thisdoc[$splitfieldidx];
			my @bursted = split(/\|/, $f);
			foreach my $b (@bursted) {
				$thisdoc[$splitfieldidx] = $b;
				say $docfh $cols,"\t", join("\t", @thisdoc);
			}
		} else {
			say $docfh $cols,"\t", join("\t", @thisdoc);
		}
	}
}

 exit(0);
#
# web cleanup: We were passed the id of the Mongodb status record on the command line.
# That record was created by the web app but we have to update it here with an endtime,
# indicating that the run completed
# By using an END block it is always entered, but is a no-op if not
# running in web environment
#


END {
    my $st = $?;
    my $k = $opth->{web};
    say STDERR "ecweb exiting with status $st" if ($k);

# web cleanup: We were passed the id of the Mongodb status record on the command line.
# add completion time, and error status if abnormal termination

   if($k){ 
    if ($st == 0) {
	    say STDERR "reporting end time to webapp";
	    ECdb::add_endtime($k);
    } else {
	    
	    $st = "exit code $st: ". $AIEerrmsg;
	    $AIEerrmsg = undef;
	    say STDERR "reporting error status $st to webapp";
	    ECdb::add_errorstatus($k, $st);
    }
  }
}


#
