#
# glom: a webserver log aggregator and statistics generator
#

use Getopt::Std;
use Config::Simple;
use DBI;
use URI;
use File::Basename;
use Data::Dumper;

use strict;
use warnings;


### Defaults

my $config_file=$ENV{'HOME'}.'/.glom';
my $logrep='/usr/bin/logrep';
my $dbhost='localhost';
my $dbport=3306;
my $tmpdir='/var/tmp/glom';

### Globals

my %conf;
our ($opt_c);


### Read and process the configuration file

sub read_config {

    if($opt_c) {
        $config_file=$opt_c;
        die "can't read $opt_c: $!" if(! -r $config_file);
    } else {
        if(! -r $config_file) {
            $config_file='/etc/glom.cfg';
            if(! -r $config_file) {
                die "can't find a config file (try using -c)";
            }
        }
    }

    Config::Simple->import_from($config_file, \%conf);

    if(defined $conf{'glom.logrep'}) { $logrep=$conf{'glom.logrep'}; }
    if(defined $conf{'glom.dbhost'}) { $dbhost=$conf{'glom.dbhost'}; }
    if(defined $conf{'glom.dbport'}) { $dbport=$conf{'glom.dbport'}; }
    if(defined $conf{'glom.tmpdir'}) { $tmpdir=$conf{'glom.tmpdir'}; }

    die "one or more of dbuser, dbpass or dbname not defined in $config_file"
        if(!defined($conf{'glom.dbuser'}) || !defined($conf{'glom.dbpass'}) || !defined($conf{'glom.dbname'}));
}


### Fetch a logfile to process
###   fetch_logfile(logfile_id, logfile_uri)

sub fetch_logfile($$) {
    my $uri=URI->new($_[1]);
    my $logfile="$tmpdir/id$_[0]".$uri->host.'-'.basename($uri->path);

    if($uri->scheme eq 'ssh') {
        system('scp '.$uri->user.'@'.$uri->host.':'.$uri->path.' '.$logfile);
    } elsif($uri->scheme eq 'file') {
        system('cp '.$uri->path.' '.$logfile);
    } else {
        warn "unknown URI sceme for $_[1]";
        return 0;
    }

    if(! -r $logfile) {
        warn "failed to fetch $_[1]";
        return 0;
    }

    my @st=stat($logfile);
    if(time()-$st[9] > 2) {  
        warn "failed to fetch $_[1] ($logfile is more than 2 seconds old)";
        return 0;
    }

    return 1;
}


### PROGRAM ENTRY POINT

getopt('c:');

read_config();

umask 0077;

if(! -d $tmpdir) {
    die "can't mkdir $tmpdir: $!" unless mkdir($tmpdir);
}

my $dbh=DBI->connect('DBI:mysql:database='.$conf{'glom.dbname'}.";host=$dbhost;port=$dbport",
    $conf{'glom.dbuser'}, $conf{'glom.dbpass'}, {'RaiseError' => 1});

my $logfiles=$dbh->selectall_hashref('select id,uri,unix_timestamp(last_retrieved) as ts from logfiles', 'id');
my $metrics=$dbh->selectall_hashref('select * from metrics', 'id');

die 'no logfiles defined' if(scalar(keys(%$logfiles))==0);
die 'no metrics defined' if(scalar(keys(%$metrics))==0);

foreach my $logfile (keys %$logfiles) {
    next if(!fetch_logfile($logfiles->{$logfile}{'id'}, $logfiles->{$logfile}{'uri'}));

    $dbh->do('update logfiles set last_retrieved=now() where id='.$logfiles->{$logfile}{'id'});

    my $result;
    foreach my $metric (keys %$metrics) {
        my $cmd=$metrics->{$metric}{'cmd'};
        if($metrics->{$metric}{'do_subs'}) {
            $cmd=~s/\$TIMESTAMP\$/$logfiles->{$logfile}{'ts'}/;
        }
        print "RUNNING: $cmd\n";
        if(!open CMD, "$cmd|") {
            warn $logfiles->{$logfile}{'uri'}.": failed to run $cmd";
            next;
        }
        $result=<CMD>;
        close CMD;

        if(!$result) {
            warn $logfiles->{$logfile}{'uri'}.": result of \"$cmd\" is empty";
            next;
        }

        print "RESULT: $result\n.\n";

        (my $count)=$dbh->selectrow_array('select count(*) from results where '.
            'log_id='.$logfiles->{$logfile}{'id'}.' and met_id='.$metrics->{$metric}{'id'});

        if($count==0) {
            $dbh->do('insert into results (log_id,met_id,value,last_updated) values ('.
                $logfiles->{$logfile}{'id'}.','.$metrics->{$metric}{'id'}.",'$result',now())");
        } else {
            $dbh->do("update results set value='$result',last_updated=now() where ".
                'log_id='.$logfiles->{$logfile}{'id'}.' and met_id='.$metrics->{$metric}{'id'});
        }
    }
}
