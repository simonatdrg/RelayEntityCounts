#!/usr/bin/perl
package doQuery;
#
# given a query object, return counts, docid list, both ...
##
use strict;
use 5.012;
use Relay::Common qw(logme $RELAY_DATA $RELAY_LOGD);
use Relay::BufferedAttivioQuery;
use ecConfig;
use Carp;
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
# do the AIE query
# v1: counts only (#opth will eventually have options for the query)
sub _dothisquery {
	my ($self, $opth) = @_;
	my $baseurl = $opth->{url};
	my $hasfacets = undef;
	my $a = Relay::BufferedAttivioQuery->new();
	if($baseurl) {
		$baseurl=~s!/$!!; # url can't have trailing slash
		$a->baseurl($baseurl) 
	}
#	
# handle query /filters
#
    my $qparms = $self->_makequery();
    $a->query($qparms->{query});
    $a->qtype($qparms->{qtype});
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
      if ($self->{qry}->fields()) {
         $a->fields($self->{qry}->fields());
      }
	}
	# all set up ... ready to do query: Save the URL for testing/debugging
	$self->{url} = $a->URL();
#say STDERR "doing ",$a->URL();	
	if ($opth->{querytype} =~ /counts/ims) {
         my $doc = $a->nextdoc(); # will execute the query so we can grap counts and
         # facets if requested
         my $rset = $a->ResultSet();
         if (! defined $rset) {
			$self->{numrows} = undef;
			return;
		}
		$self->{numrows}  = $rset->status()->{totalRows};
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
		 while (( my $doc = $a->nextdoc())) {
                  if (! $self->{numrows}) {
                     # save it the first time through
                     $self->{numrows}  = $a->ResultSet()->status()->{totalRows};
                  }
         # $self->{docids} will be an AoH, where each row is a hash : key id alwayw present, plus optional other fields
         my $resdoc = {};
         $resdoc->{id} = $doc->{id};
#		 foreach my $fn (@{$self->{qry}->{fields}}) {
         foreach my $fn (@{$self->{qry}->fields()}) {
            $resdoc->{$fn} = join('|',@{$doc->field($fn)});
         }
		  push @{$self->{docids}},$resdoc;
		 }
   }
	return;
}

sub _makecomplexquery {
   my ($self) = @_;
    my $qry = $self->{qry};
    my ($query, @fqarr, $qtype);
	$qtype = 'advanced';
	my $aquery ='';
	my $fq;
	foreach  $fq (@{$qry->filters()}){
#	foreach  $fq (@{$qry->{filters}}){
	  my ($qt,$body) = split(/#/, $fq);
	}
}
#
# _makequery: looks at the filters, and generates query /filter/querytype
# OR queries will use advanced mode syntax.
# FILTER(*:*, OR(o1,o2,o3...), OR(o100,0101))
# Multiple OR queries get wrapped in an AND 
# 
sub _makequery {
    my ($self) = @_;
    my $qry = $self->{qry};
    my ($query, @fqarr, $qtype);
    $qtype = 'simple';

    my @orq = ();
    @orq = grep { $_ =~ /^ORQ#/i } @{$qry->filters()};
    # if we have or queries, generate the advnaced syntax query
    my ($oq);
    for (my $j = 0 ; $j < scalar(@orq) ; $j++) {
        $orq[$j] =~ s/^ORQ#://;
        $orq[$j] =~ s/\sOR/,/g;
        $orq[$j] = sprintf('FILTER(*:*, OR(%s))', $orq[$j]);
    }
    # if more than one or query, wrap in AND()
    if (scalar @orq > 1) {
        $query = sprintf('AND(%s)', join(",", @orq));
        $qtype = 'advanced';
    } elsif (scalar @orq == 1) {
        $qtype = 'advanced';
        $query = $orq[0];
    } else { # no orq, do everything as fqs
#	  $qtype = 'simple';
	  $query = '*:*';
	  
    }
	
	  if (defined ($self->{qry}->{rawquery})) {
		
        my $q = $self->{qry}->{rawquery}->[0];
		 say STDERR "working on raw query $q";
	    if ($q =~ /^raw!/i) {
			$q =~ s/^raw!//i ;
			$query = $q;
			$qtype='advanced';
        }
    } 
# 
# look for non-or filters
#
    my @fqin = grep { $_ !~ /^ORQ#/i } @{$qry->{filters}};
    for (my $j = 0 ; $j < scalar(@fqin) ; $j++) {
         next if ($fqin[$j] =~ /NULL!/i);
		 # remove the leading tag type
        $fqin[$j] =~ s/^(.*?)#//;
        push @fqarr, $fqin[$j]; 
    }
    return {query => $query, filterquery => \@fqarr, qtype => $qtype};
}
1;
__END__

$VAR1 = {
          'fulltext' => '*:*',
          'filters' => [
                         'all_facet_date:[2008-04-03 TO 2008-06-30]',
                         'table:medline',
                         'diseases_ent:"asthma"',
                         'diseases_ent:"measles"',
                         'drugs_ent:"aspirin"',
                         'genes_ent:"p51"'
                       ],
          'facets' => undef
        };
$VAR1 = {
  'fulltext' => '*:*',
  'filters' => [
    'all_facet_date:[2008-04-03 TO 2008-06-30]',
    'table:medline',
    'diseases_ent:"asthma"',
    'diseases_ent:"measles"',
    'drugs_ent:"aspirin"',
    'genes_ent:"p52"'
  ],
  'facets' => undef
};

