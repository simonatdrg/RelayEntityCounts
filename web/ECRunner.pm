package ECRunner;
# class to set up and run the EC utility with a supplied config file
# and other command line options
# typical use case is to be called from a web app
#
# Status information will be persisted in mongodb
#
# Where things are:
#
# $RELAY_DATA/temp/ec - uploaded config files and staging for results files
# 
# 
use strict;
use 5.012;
#use Class::DBI;
use DBI;
#use Relay::Common qw(logme $RELAY_DATA $RELAY_LOGD);
use Moose;
use File::Slurp;
use Env qw (HOME);
use IPC::System::Simple qw (system systemx capture capturex EXIT_ANY);
use ecwebconsts qw ($ECTEMPDIR $ECSCRIPT);
use Storable qw (freeze thaw);
use Time::HiRes;
use Data::Dumper;
#our $TEMP = "$RELAY_DATA/temp/ec";
# our $ecscript = "${HOME}/relay-analysis/perl/ec.d/ec.pl"; # don't forget to change

our $dbh = undef;
# 
	has 'configfilepath', is => 'rw', isa => 'Str';
	has 'docounts', is => 'rw', isa =>'Int';
	has 'dodocs', is => 'rw', isa =>'Int' ;
	has 'comment', is => 'rw', isa => 'Str';
    has 'url',  is => 'rw', isa => 'Str', default => "http://localhost:17001";
	has 'logfile', is => 'rw', isa =>'Str';
	has 'runid', is => 'rw', isa =>'Str';
	has 'user', is => 'rw', isa =>'Str';

sub checkconfig {
    my ($self) = @_;
    my $tempf = "${ECTEMPDIR}/ecerr.$$";
    $self->logfile($tempf);
    my $cmd = sprintf("perl %s -c %s --test 2>%s 1>/dev/null",
                      $ECSCRIPT, $self->configfilepath(), $tempf);
    say STDERR "running $cmd\n";
    my $st = system(EXIT_ANY, $cmd);
#    say STDERR "exit status was $st";
    if ($st > 0) {
#	say STDERR "Errors encountered in config - please check\n----";
	my $t = read_file($tempf);
#	say $t;
        unlink $tempf;
        return($st, $t);
	    }
    # config was OK
    unlink $tempf;
    return (0, undef);
}

sub run {
    my ($self, $user, $runmode) = @_;
    # runmode: sync (wait) or async
    # if async we need to record the run and return an identifier
    # for status checks
    #
    my ($sec, $usec) = Time::HiRes::gettimeofday();
    # runid accurate to millisecond, they repeat after a year ....
    my $runid = sprintf("%d_%d", $sec % (86400*365), int($usec/1000) );
    $self->runid($runid);
    my $errf = "${ECTEMPDIR}/ecerr.${runid}";
    
    # TODO: instantiation for doc ids
    my $resfile = "${ECTEMPDIR}/${runid}_results.txt";
    # set up the run record for MongoDB
    my $runopt = $self->dodocs() ? "-d $resfile " : "";
#    say STDERR "cts/rows = $runopt";
    my $runrec = { _id => $runid,
                   config => $self->configfilepath,
                   type => $self->dodocs() ? 'docs' : 'counts' ,
                   output => $resfile,
		           starttime => time(),
		           endtime => undef,
                   user => $user,
                   comment => $self->comment()};
    ECdb::savestatus($runrec);
    #
    # say STDERR "starting ec : log = $errf, out = $resfile";
    #
    my $cmd = sprintf("perl %s -c %s  -u '%s' %s --web=%s 2>%s 1>%s %s",
                      $ECSCRIPT, $self->configfilepath(),
		      $self->url(),
		      $runopt,
		       $runid,
		      $errf, $resfile,
                      '&');
    #
    say STDERR "starting $cmd\n";
    my $st = system(EXIT_ANY, $cmd);
    say STDERR  "running cmd";
    my $status = $self->efreeze();
 #   say STDERR "status blob length =".length($status);
    return $runid;
}

# given a jobid, return the associated object
sub status {
    my ($self) = @_;
    
}
# freeze/thaw object to go in session cookie
sub efreeze {
    my ($self) = @_;
    return freeze($self);
}
# return a frozen ECRunner object,
# 
sub ethaw {
    my ($blob) = @_;
    my $s = thaw($blob);
    say STDERR "thawed obj is a ",ref($s);
    return $s;
}

sub BUILD {
    	my ($self, $args) = @_;
	# 
	return $self;
}

__PACKAGE__->meta->make_immutable;

#
# mongodb  database access methods
#
package ECdb;

use strict;
use warnings 'all';
use MongoDB;
use Data::Dumper;

use Exporter ();
#use vars qw( @EXPORT); 	
our @ISA       = qw(Exporter);
#
use vars qw ($DB $STATUSTABLE );
# mongo setup
our $DB = "ecweb";
our $STATUSTABLE = 'ecwebjobs';
our $mcl = MongoDB::MongoClient->new();
our $mdb = $mcl->get_database($DB);
our $mstatus = $mdb->get_collection($STATUSTABLE);
 
# save a batchjob status: Set when the batch job is initiated
# The hash contains:
# _id field 
# starttime (unix ts)
# config file
# run type (counts or docs)
# output file
# comment
# baseurl
# end time -- gets added at end
# OID is returned

sub savestatus {
    my ($ph) = @_;
    my $id = $mstatus->insert($ph);
    say "saved runrec id=$id";
    return $id;
}
# add terminating time: called by ec.pl on termination. We use an endtime to inidcate
# that the job completed
#
sub add_endtime {
    my ($id) = @_;
    my $tm = time() ;
    $mstatus->update({"_id" => $id}, { '$set' =>{'endtime' => $tm}});
}

sub add_errorstatus {
    my ($id, $code) = @_;
    my $tm = time() ;
    $mstatus->update({"_id" => $id}, { '$set' =>{'endtime' => $tm}});
    $mstatus->update({"_id" => $id}, { '$set' =>{'error' => $code}});

}
# get single status record by jobid
sub  getStatusRecord {
    my ($id) = @_;
#    say  STDERR "getStatusRecord#".$id;
    my $rec = $mstatus->find_one({'_id' => $id});
    print Dumper($rec);
    return $rec;
}

# get all status records since a specific time
sub getManyRecords {
    my ($start) = @_; #unix time
#   my $sort = {"starttime" => -1};  #TODO ... change find below to get sorted output
#   my $cursor = $coll->query->sort($sort);
    my $cursor = $mstatus->query({'starttime' => { '$gte' => $start}}, {sort_by => {"starttime" => -1}});
    return $cursor;
}
# delete all status records before a specific time
sub cleanStatusRecords {
    my ($before) = @_;  # unix time
    $mstatus->remove({'starttime' => { '$le' => $before }});
}

1;
