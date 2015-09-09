package ecConfig;

use Config::Properties;
use Getopt::Long;
use Carp;
use IO;
use Try::Tiny;
use Relay::Common qw(logme $RELAY_DATA $RELAY_LOGD);
use Date::Parse;
use Data::Dumper;
use Text::ParseWords;
use constructQuerySet;
use strict;
use warnings;
use 5.012;

# need to deal with sdtin
sub new {
    my ($proto, $configfile, $clargs)= @_;
    my ($self) ={};
    my $class = ref($proto) || $proto or return;
	my $cfh;
	if ($configfile eq *STDIN) {
		$cfh = *STDIN;
	} else {
	open  $cfh, '<', $configfile
		or croak ("unable to open configuration file $configfile");
	}
# deal with possible DOS line endings
	binmode $cfh, ":crlf";	
	my $props = Config::Properties->new();
	$props->load($cfh);
	$self->{cf} = $props;
	$self->{docoutput} = $clargs->{docs};
	bless $self, $class;
	$self->doconfig($clargs);
	return $self;
}

sub doconfig {
  # popt is preparsed command line hash from getOpt::Long;
  my ($self, $popt) = @_;
  my ($t);
  my $errcnt = 0;
  my $norowprocessor = exists($popt->{norowp});
#  $self->{aiehost} = $popt->{host};
#  $self->{aieport} = $popt->{port};
  # get stuff on the command line
  $self->{debug} = $popt->{debug};
  my $testmode = $popt->{test} ;
  # say STDERR "Just checking configuration" if ($testmode);
  # if testmode then don't fail outright on config file errors, logthem instead
  my $level = "notice";
  #
  #  get items we want, including any command line overrides
  #
  
  #dates - validate format, start <= end
  $self->{startdate}= $self->{cf}->getProperty('startdate') || '1995-01-01';
  $errcnt++, logme($level, sprintf("startdate %s is not in yyyy-mm-dd format", $self->{startdate}))
		unless ($self->{startdate} =~ m/\d{4}-\d{2}-\d{2}/ );
  my @now = localtime();		
  $self->{enddate}= $self->{cf}->getProperty('enddate') ||
	sprintf("%04d-%02d-%02d", $now[5]+1900, $now[4]+1, $now[3]); 
  $errcnt++, logme($level, sprintf("enddate %s is not in yyyy-mm-dd format", $self->{enddate}))
		unless ($self->{enddate} =~ m/\d{4}-\d{2}-\d{2}/ );
  $errcnt++, logme($level, 'startdate must be before enddate')
	if (($self->{startdate} && $self->{enddate}) && str2time($self->{'enddate'}) < str2time($self->{'startdate'}));
	
  #
  # default date range is quarterly
  # must specify something since there are default dates
  #
  
  $t = $self->{cf}->getProperty('dateresolution') || 'quarterly';
  # legal values are quarterly,range,none
  if ($t =~ m/(quarter|range|none|year)/) {
	$self->{dateresolution} = $t;
  } else {
	$errcnt++, logme($level, "date resolution must be one of quarterly,yearly, range or none");
  }
  
  #
  my @srclist;
  my $srcline = $self->{cf}->getProperty('sources');
  if (! defined $srcline) {
	$errcnt++, logme ($level, "Must specify a set of source(s)");
  } else {
    @srclist =  split( /\s*,\s*/, $srcline) ;
    $self->{sources} = \@srclist;
  }
  # look for static output tags and save
  my  $ohash = $self->{cf}->splitToTree(qr /(?<=outputtag)/,'outputtag');
  
  # other fields to output, if doing docid search
  $self->{otherfields}= $self->{cf}->getProperty('otherfields');
  
  my @otags = ();
  foreach my $t (sort keys %{$ohash}) {
    push @otags, $ohash->{$t}; # get the ordered set of tags
  }
  $self->{otags} = \@otags;    
  # 
  my $chash = $self->{cf}->splitToTree(qr /(?<=tity)\./,'inputentity');
#  if (scalar (keys %$chash) == 0) {
#	$errcnt++, logme($level, "You must supply at least one 'inputentity.<entityname>' line !");
#  } else {
    $self->{inputentity} = $chash;
    $self->{entityorder} = [sort keys %$chash];
    $self->{discover} = $self->{cf}->getProperty('discover');
	# andle multiple fulltexts ?
	my $fthash = $self->{cf}->splitToTree(qr /(?<=fulltext)\./,
										  'fulltext');
    $self->{fulltext}  = $fthash if (scalar(keys %$fthash) > 0);
    if ((scalar (keys %$chash) == 0) && (scalar (keys %$fthash) == 0)) {
	$errcnt++, logme($level, "You must supply at least one 'inputentity.<entityname>' or 'fulltext' line !");
  } else {
	# a single raw query ... duffers from fulltext in that it it is a complete AIE advanced query
    $self->{rawquery}  = $self->{cf}->getProperty('rawquery');
    
    $self->{qs}  = constructQuerySet->new($self) unless ($testmode);
  }
  if ($testmode) {
    if ($errcnt) {
	say  STDERR "$errcnt errors detected in configuration file";
	exit(1);
    }
    # otherwise OK
    say STDERR "Exiting from ec running in test configuation mode";
    exit(0);
  }
  if ($errcnt > 0) {
    croak "Errors encountered in config file";
    #code
  }
  
  
 # sleep 1;
}

# dump configuration
sub prettyprint {
	my ($self) =@_;
	my $d =Data::Dumper->new([$self]);
	print STDERR $d->Dump;
	return 0;
}
1;
