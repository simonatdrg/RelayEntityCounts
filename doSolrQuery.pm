#!/usr/bin/perl
package doSolrQuery;
#
# given a query object, return counts, docid list, both ...
##
use strict;
use 5.012;
use Relay::Common qw(logme $RELAY_DATA $RELAY_LOGD);
use Relay::BufferedSolrQuery;
use ecConfig;
use Carp;
use Try::Tiny;
#use Data::Dumper;

sub new { 
   my ($proto, $qry, $params)= @_;
    my ($self) ={};
    my $class = ref($proto) || $proto or return;
	my $cfh;
    $self->{qry} = $qry;
	bless $self, $class;
	$self->_dothisquery($params);
	return $self;
}
#
# do the Solr query
# v1: counts only (#opth will eventually have options for the query)
sub _dothisquery {
	my ($self, $opth) = @_;
	my $baseurl = $opth->{url};
	my $hasfacets = undef;
	my $a = Relay::BufferedSolrQuery->new();
	if($baseurl) {
		$baseurl=~s!/$!!; # url can't have trailing slash
		$a->baseurl($baseurl);
	}
   $a->collection($opth->{collection});
   
#	
# handle query /filters
#
    my $qparms = $self->_makequery();
    $a->query($qparms->{query});
    #$a->qtype($qparms->{qtype});
    foreach my $f (@{$qparms->{filterquery}}) {
        $a->filterquery($f);
    }
    goto qdone;
	$a->query("*:*"); #default
    # if a raw query, then that's the main query
    if (exists ($self->{qry}->{rawquery})) {
        my $q = $self->{qry}->{rawquery}->[0];
	    if ($q =~ /^raw!/i) {
			$q =~ s/^raw!//i ;
			$a->query($q);
        }
    } 
	# the 'filters' also include fulltext (tagged as such), 
	foreach my $fq ( @{$self->{qry}->filters()}) {
      # TODO: check for NULL! and obviously don't add it
         next if ($fq =~ /NULL!/i);
		 $a->filterquery($fq);
	}
qdone:	
   if ($opth->{querytype} =~ /counts/i) {
         # we need to ask for one row so that the bufferedattivioquery will
         # actually do a query  
	  $a->numrows(1);
      $a->requestsize(1); # and make the actual query small as well
      if (my $fs = $self->{qry}->facets()->[0]) {
		$hasfacets = 1;
         $a->facetspec({name =>$fs, maxBuckets => 200000 });
        }
   } else {
         # docs ... assume the worst...
	  $a->numrows(30000000);
      $a->requestsize(2000);
      # add output fields if they were specified
	  my @fwanted = ('id');  # always
      if ($self->{qry}->fields()) {
		 push @fwanted, @{$self->{qry}->fields()};
         $a->fields([@fwanted]);
      }
	}
	# all set up ... ready to do query: Save the URL for testing/debugging
	$self->{url} = $a->SolrURL();
# say STDERR "doing ",$a->SolrURL();	
	if ($opth->{querytype} =~ /counts/ims) {
         my $rset = $a->getdocs(); 
         # facets if requested
         # my $rset = $a->SolrResultSet();
         if (! defined $rset) {
			$self->{numrows} = undef;
			return;
		}
		$self->{numrows}  = $rset->totalrows();
		$self->{facets} = undef;
		if ($hasfacets) {
            my $fres = $rset->facetset();
		$self->{facets} = $fres;	
		}
	}
    #
   if ($opth->{querytype} =~ /doc/ims) {
	  # get docids, ignore facets, include other fields
		 $self->{docids} = [];
		 my $doc;
		eval {
			while (( $doc = $a->nextdoc())) {	
			   if (! $self->{numrows}) {
						# save it the first time through
						$self->{numrows}  = $a->totaldocs();
			   }
	  
			# $self->{docids} will be an AoH, where each row is a hash : key id alwayw present, plus optional other fields
			my $resdoc = {};
			$resdoc->{id} = $doc->id();
			foreach my $fn (@{$self->{qry}->fields()}) {
			   $resdoc->{$fn} = $doc->pretty($fn,"|");
			}
			push @{$self->{docids}},$resdoc;
		 }
	  }; #end eval
	  if ($@) {
		 say STDERR $a->errorstatus();
		 say STDERR 'exiting';
		 exit(1);
	  }
	  
   }
	return;
}

#
# _makequery: looks at the filters, and generates query /filter
# We do everything as a filter query as we're not interested in scoring
# and each one will be cached thus making the interation more efficient
#
sub _makequery {
    my ($self) = @_;
    my $qry = $self->{qry};
    my ($query, @fqarr);

    my @orq = ();
    @orq = grep { $_ =~ /^ORQ#/i } @{$qry->filters()};
    # 
    my ($oq);
    for (my $j = 0 ; $j < scalar(@orq) ; $j++) {
        $orq[$j] =~ s/^ORQ#://;
		push @fqarr, $orq[$j];
    }
   $query = '*:*';  
	
	  if (defined ($self->{qry}->{rawquery})) {
		
        my $q = $self->{qry}->{rawquery}->[0];
		 say STDERR "working on raw query $q";
	    if ($q =~ /^raw!/i) {
			$q =~ s/^raw!//i ;
			$query = $q;
        }
    } 
# 
# look for non-or filters
#
    my @nonorfq = grep { $_ !~ /^ORQ#/i } @{$qry->{filters}};
    for (my $j = 0 ; $j < scalar(@nonorfq) ; $j++) {
         next if ($nonorfq[$j] =~ /NULL!/i);
		 # remove the leading tag type
        $nonorfq[$j] =~ s/^(.*?)#//;
        push @fqarr, $nonorfq[$j]; 
    }
    return {query => $query, filterquery => \@fqarr};
}
1;
__END__

