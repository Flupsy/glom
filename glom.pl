#
# glom: a webserver log aggregator and statistics generator
#

use Getopt::Std;
use Config::IniFiles;
use DBI;
use URI;
use Sys::Hostname;
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
my $logfile_spec='/data/vhost/*/logs/access_log';

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

    tie %conf, 'Config::IniFiles', (-file => $config_file);
    die "no [glom] section in $config_file" if(!defined($conf{'glom'}));

    if(defined $conf{'glom'}{'logrep'}) { $logrep=$conf{'glom'}{'logrep'}; }
    if(defined $conf{'glom'}{'dbhost'}) { $dbhost=$conf{'glom'}{'dbhost'}; }
    if(defined $conf{'glom'}{'dbport'}) { $dbport=$conf{'glom'}{'dbport'}; }
    if(defined $conf{'glom'}{'tmpdir'}) { $tmpdir=$conf{'glom'}{'tmpdir'}; }
    if(defined $conf{'glom'}{'logfile_spec'}) { $logfile_spec=$conf{'glom'}{'logfile_spec'}; }

    die "one or more of dbuser, dbpass or dbname not defined in $config_file"
        if(!defined($conf{'glom'}{'dbuser'}) || !defined($conf{'glom'}{'dbpass'}) || !defined($conf{'glom'}{'dbname'}));
}


### PROGRAM ENTRY POINT

getopt('c:');

read_config();

umask 0077;

if(! -d $tmpdir) {
    die "can't mkdir $tmpdir: $!" unless mkdir($tmpdir);
}

my $dbh=DBI->connect('DBI:mysql:database='.$conf{'glom'}{'dbname'}.";host=$dbhost;port=$dbport",
    $conf{'glom'}{'dbuser'}, $conf{'glom'}{'dbpass'}, {'RaiseError' => 1});

my $metrics=$dbh->selectall_hashref('select * from metrics', 'id');

die 'no metrics defined' if(scalar(keys(%$metrics))==0);

foreach my $file (glob $logfile_spec) {
    my $logfile=$dbh->selectrow_hashref("select id,filename,unix_timestamp(last_retrieved) as ts from logfiles where filename='$file'");
    if(!$logfile) {
        $dbh->do("insert into logfiles (filename) values ('$file')");
        $logfile=$dbh->selectrow_hashref("select id,filename,unix_timestamp(last_retrieved) as ts from logfiles where filename='$file'");
    } else {
        $dbh->do("update logfiles set last_retrieved=now() where id='$$logfile{'id'}'");
    }

    my $result;
    foreach my $metric (keys %$metrics) {
        my $cmd=$metrics->{$metric}{'cmd'};
        if($metrics->{$metric}{'do_subs'}) {
            $cmd=~s/\$TIMESTAMP\$/$$logfile{'ts'}/;
            $cmd=~s/\$LOGFILE\$/$file/;
        } else {
            $cmd.=" $file";
        }

        if(!open CMD, "$cmd 2>/dev/null |") {
            warn "$file: failed to run $cmd";
            next;
        }
        $result=<CMD>;
        close CMD;

        next if(!$result);

        chomp $result;
        $dbh->do("replace into results (log_id,met_id,value,last_updated) values (".
            "$$logfile{'id'},$metrics->{$metric}{'id'},'$result',now())");
    }
}
