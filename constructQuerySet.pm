#
package constructQuerySet;
# handle AIE (filter) query construction using the entity field information passed in the
# configuration.
use strict;
use Relay::Common qw(logme $RELAY_DATA $RELAY_LOGD);
use Carp;
use Text::ParseWords;
use Try::Tiny;
use File::Slurp;
use Set::CrossProduct;
use List::MoreUtils qw (any);

use parent qw(Set::CrossProduct);
# constructor:
# take the defined configuration and create a complete set of AIE queries
# which can be returned to an iterator
#
#
sub new {
	my ($proto, $cf)  = @_;
    my ($self) ={};
    my $class = ref($proto) || $proto or return;
	my $cfh;
	bless $self, $class;
	$self->{queryset} =$self->makeQuerySet($cf);
	$self->{queryctr} = 0;
	return $self;
}
# do the hard work of creating the complete set of queries for this instance of ec
# we loop through all the entity defs, sources, and date specs to create an arry of
# query spec objects which can be returned to the 
sub makeQuerySet {
	my ($self,  $cfg) = @_;
	my $qobj = {};
	my $efilters = {};
	my $facet = [];
	my $text = [];
	# default for the fulltext part
	$self->{fulltext} = [ '*:*'];
	
	# fulltext: break into multiple phrases (same as entities)
	if ( defined $cfg->{fulltext}) {
		$text = _generate_fulltext_query_set($cfg);
		$self->{fulltext} = $text;
	}
	# we can have a single raw query, used verbatim
    if ( defined $cfg->{rawquery} ) {
#        print STDERR "rawquery not currently supported\n";
 #       exit;
        $text = [ 'raw!'.$cfg->{rawquery} ];
		$self->{rawquery} = $text ;
    }
#
#
	$efilters = _generate_entity_filterquery_set($cfg);
	$self->{otherfields} = _split_outputfields($cfg->{otherfields});

	if ($cfg->{discover}) {
# a single facet ...
		 $facet = [_normalize ($cfg->{discover})];
	}
	my ($datequeries, $srcfilters);
# here's the set of filter queries for date ranges
    if ($cfg->{dateresolution} =~ /quarter/) {
	#	say STDERR "quarterly queries";
	   $datequeries =
		constructQuerySet::makeQuarterFilters($cfg);
	} elsif ($cfg->{dateresolution} =~ /year/) {
		$datequeries = constructQuerySet::makeYearFilters($cfg);
	} elsif ($cfg->{dateresolution} =~ /range/) {
	#	say STDERR "single date range";
		my $field = "all_facet_date";
		$datequeries =
		[ sprintf("%s:[%s TO %s]", $field, $cfg->{startdate}, $cfg->{enddate}) ];
	} else {
		$datequeries = undef;
	}
	
	
	$srcfilters = _generate_src_filter_set($cfg);
	#
	# generate an AoA for getting the cross product of all of these...
	#
	my @setofarrays = ();
#
# the ordering in the array will determine the column ordering on output
# so ents .. source filters, dates [facet counts  or counts ]
# Defer col heading setup to query setup, where we know exactly what our search criteria are
#
	foreach my $earr (@$efilters) {
		push @setofarrays, $earr;
	}
	# if we have explicit fulltext queries, save this for the iterator
	# otherwise will default to *:* 
	push @setofarrays, @{$text}if ($cfg->{fulltext}); 
	push @setofarrays, $srcfilters;
	# may not be any dates ....
	push @setofarrays, $datequeries if ($datequeries);
 	
#generate the complete cross product, possibly including multiple fulltext queries
# (tagged as such with "text:" prepended)
#
	my $qset = Set::CrossProduct->new(\@setofarrays);
	$self->{queryset} = {
				'facets' => $facet,
				'filters' => $qset,
				'rawquery' => $self->{rawquery},
				'fields' =>$self->{otherfields}
				 };  
	
}
#
# return the next set of query parameters;
#
sub next {
	my ($self) = @_;
	my $q ={};
	my $tuple;
	return undef unless defined ($tuple = $self->{queryset}->{filters}->get());
	$q->{facets} = $self->{queryset}->{facets};
	$q->{rawquery}  = $self->{queryset}->{rawquery};
	$q->{filters} = $tuple;
	$q->{fields}  = $self->{queryset}->{fields};
    
	return ECQuery->new($q);
}

#
# helpers
#
sub _generate_src_filter_set {
	my ($cfg) = @_;
	my @s = ();
	foreach my $src (@{$cfg->{sources}}) {
		$src = lc $src;
		push @s, "table:$src";
	}
	return \@s;
	#return ['table:medline','table:nih'];
}
# fulltext queries from fulltext.1, .2 ...
sub _generate_fulltext_query_set {
		my ($cfg) = @_;
		my @qarr = (); 
		foreach my $ftkey (sort keys %{$cfg->{fulltext}}) {
				my @thisearr = ();
		#		say STDERR "ft key 2";
				# process fulltext.<n>
				my $pvals = _split_entvals($cfg->{fulltext}->{$ftkey});
		# an array with "content:<query term>" elements
				foreach my $ftval (@$pvals) {
# if it has ' term OR term2 OR ...' then we need to enclose in parens
                        if($ftval =~ /\sOR\s/) {
                #            $ftval = "(" . $ftval . ")";
							push @thisearr, sprintf('%s:%s', "ORQ#", $ftval);
                        } else {  # if no parens, then surround qry with quotes if not already quoted
						my $qch = ($ftval =~ /^".*"/) ? "": '"';
						push @thisearr, sprintf('%s:%s%s%s', "FTQ#", , $qch, $ftval, $qch);
						}
				}
		push @qarr, \@thisearr;
		}
	return \@qarr;
				
}
# return pointer to array of all possible entity filter query combinations:
# each element is itself a set of filter queries
# 
sub _generate_entity_filterquery_set {
	my ($cfg) = @_;
	my @qarr = ();
	
	foreach my $edef (@{$cfg->{entityorder}}) {
		my @thisearr = ();
		# this takes the properties value and returns the actual field associated with it
		my $normalized_def = _normalize($edef);
		my $pvals = _split_entvals($cfg->{inputentity}->{$edef});
		foreach my $eval (@$pvals) {
			# embedded ORs
			if ($eval =~ /\sOR\s/) {
				my $rewritten = _expand_orquery($normalized_def, $eval);
				push @thisearr, sprintf('%s:%s', "ORQ#", $rewritten);
			} else {
				$eval = '"'.$eval.'"' unless ($eval =~ /"/); #surround by quotes if notalready there
				push @thisearr, sprintf('%s:%s', $normalized_def, $eval);
			}
		}
		push @qarr, \@thisearr;
	}
	return \@qarr;
}

#####
# rewrite a query with ors to field:term1 OR field:term2 .....
sub _expand_orquery {
	my($field, $qin) = @_;
	my $rewrite='';
	my @terms = split(/\s+OR\s+/, $qin);
	$rewrite .= "$field:".$_." OR " foreach (@terms);
	# remove trailing OR
	$rewrite =~ s/\s+OR\s+$//;
	return $rewrite;
}

sub _split_outputfields {
	my ($str) = @_;
	my @a = parse_line('\s*,\s*', 0, $str);
	return \@a;
}
#
# return an arrayptr with the whitespace separated entities split
# text::parsewords::parse_line handles quoted values
# 12/2013: handle syntax to read a file on the fly: each line is a single
# entity to use
# (TODO): maybe expand to arbitrary backquoted command ???
#
sub _split_entvals {
	my ($str) = @_;
    my @a = ();
    if (my ($path) = $str =~ /readfile\s+(.*)$/i) {
    print STDERR "reading terms from file $path\n";
        try {
        @a = read_file($path, chomp => 1);
        } catch {
            print STDERR "couldn't do readfile $path for terms: $_\n";
            exit(1);
        };
    print STDERR scalar @a, " terms read\n";
    } else {
	    @a = parse_line('\s*,\s*', 0, $str);
    }
	return \@a;
}
# we add the tags text! to the full text field as a marker
# when we get to construct the query, the text tag will be stripped off
# and the remainder gets put in the main query field. Thatwill allow us to
# use extended syntax for a main query if desired
#  OBSOLETE 9/19
sub _split_fulltext {
	my ($str) = @_;
	my @a = parse_line('\s*,\s*', 0, $str);
	@a = map { $_ = "text!$_"; $_ }  @a;
	return \@a;
}
#
# take the property key, which may be in any of the forms
# 		diseases
#		diseases_ent
#       diseases.<number>
#       diseases_ent.<number>
#  pass through unchanged any field which isn't in this form (e.g. drugs_raw)
#and return the entity field (remembering that 'mesh' is the full field name)
sub _normalize {
	my ($s) = @_;
	my @a = split(/\./, $s);
	return $a[0] if (($a[0] eq 'mesh') || ($a[0] =~/_ent$/)) ;
    if($a[0] =~ m/^(diseases|drugs|genes|companies|people)$/) {
	    return $a[0]."_ent";
    }
    #otherwise treat as an arbitrary field and return unchanged: caveat emptor
    return $a[0];
}
#makequarterfilters: Return an array of filter queries which filter on the quarters specified in the startdate/enddate range

our @quarterfmt = (
	'%s:[%s-01-01 TO %s-03-31]',
	'%s:[%s-04-01 TO %s-06-30]',
	'%s:[%s-07-01 TO %s-09-30]',
	'%s:[%s-10-01 TO %s-12-31]'
	);


sub makeQuarterFilters {
	my ($cf, $field)=@_;
	$field ||= 'all_facet_date';
	my @filters = ();
	my $stdate = $cf->{startdate};
	my $endate = $cf->{enddate};
	my ($startyr,$startmonth) = $stdate =~ m/(\d+)-(\d+)/;
	my ($endyr,$endmonth) =     $endate =~ m/(\d+)-(\d+)/;
	my $startqoffset = _month2quarter($startmonth);
	my $endqoffset = _month2quarter($endmonth);
	my $qc = $startqoffset;
	my $yc = $startyr;
	my $nc = 0;
	my $f; 
#    print STDERR "start $yc end $endyr\n";
	while ($yc <= $endyr) {
        last if (($yc == $endyr) && ($qc > $endqoffset)); 
		 $f = sprintf($quarterfmt[$qc], $field, $yc, $yc);
		if ($nc == 0) {
			$f=~ s/\[\d+-\d+-\d+/[$stdate/;
		}
		push @filters, $f;
#		print STDERR $filters[-1],"\n"; 
		$qc++; $nc++;
#		if ($qc > 3) { $qc=0; $yc++; next; }
		if ($qc > 3) { 
            $qc=0; 
            $yc++;  
        }
	}
	$filters[-1] =~ s/\d+-\d+-\d+]$/$endate]/;
	return \@filters;
	
}

sub _month2quarter {
	my ($m) = @_;
	return 0 if (($m >=1) && ($m <=3));
	return 1 if (($m >=4) && ($m <=6));
	return 2 if (($m >=7) && ($m <=9));
	return 3 if (($m >=10) && ($m <=12));
	return undef;
}

our $yearformat = "%s:[%s-01-01 TO %s-12-31]";

sub makeYearFilters {
	my ($cf, $field) = @_;
	$field ||= 'all_facet_date';
	my @filters = ();
	my $stdate = $cf->{startdate};
	my $endate = $cf->{enddate};
	# keep month/day around in case we decide to do partial years at begiing or end
	my ($startyr,$startmonth, $startday) = $stdate =~ m/(\d+)-(\d+)/;
	my ($endyr,$endmonth, $endday) =     $endate =~ m/(\d+)-(\d+)/;
	my $yc = $startyr;
	my $nc = 0;
	my $f;
	while ($yc <= $endyr) {
		$f = sprintf($yearformat, $field,$yc,$yc);
		push @filters, $f;
		$yc++;
	}
	return \@filters;	
}
#
# encapuslate query info in an object ...
# 
package ECQuery;

sub new {
    my ($class, $h) = @_;
    bless $h, $class;
    return $h;
}
# accessors
sub facets {
	my ($self) = @_;
	return $self->{facets};
}
sub rawquery   {
	my ($self) = @_;
	return $self->{rawquery};
}

sub filters {
		my ($self) = @_;
	return $self->{filters};
}
# a fieldname may contain a /split option which will cause output to burst
#
sub fields {
     my ($self) = @_;
	 # don't alter the stored fields
	 my @temp = @{$self->{fields}};
	 my @fieldswithoutqualifier = map { $_ =~ s!\s*/split!!i; $_}  @temp;
	 return \@fieldswithoutqualifier;
#	return $self->{fields}; 		
}
# does this field have the split-on-output flag ?
sub splitonoutput {
	my ($self,$fname) = @_;
	return any { $_ =~  m!$fname\s*/split!i } @{$self->{fields}};
}

# return the first field in field list that has /split option
# may change in the future, if we can ever work out how to write out multiple  splittable fields
#
sub find_burstfield {
	my ($self) = @_;
	foreach my $f (@{$self->{fields}}) {
		if ($f =~ m!^(.*)/split! ) {
			return $1;
		}
	}
	return undef;
}
1;
