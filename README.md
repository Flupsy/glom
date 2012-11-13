glom
====

Glom is designed to fetch logfiles from lots of different servers and run some tests
on them.  It stores the results so that they can be read out by a cacti script resulting
in some pretty graphs.

At the moment there is no front end, so you'll have to put rows in the database by hand
to make it work.  Create a mysql database with `schema.sql` and put the access details
in a `.glom` file in your home directory, e.g.

    [glom]
    dbname=glom
    dbuser=glom
    dbpass=whatever_you_set_it_to

Then put a row into the `logfiles` table for each log you want to watch, e.g.

    INSERT INTO logfiles (name,uri) values \
        ('My webserver','ssh://hostname/var/log/access_log');

You'll then need to define the tests you want to run.  I wrote this thing with `logrep`
in mind, so you could add something like

    INSERT INTO metrics (name,cmd) values ('Average response time (ms)'), \
        ('/home/ian/wtop-0.6.3/logrep -o \'avg(msec)\' -f \'ts>$TIMESTAMP$\' $LOGFILE$');

If the `do_subs` flag is set for that row (and it will be by default), the metavariables
`$TIMESTAMP$` and `$LOGFILE$` will be substituted.  `$TIMESTAMP$` will be the Unix time of the
log's *last* retrieval (i.e. the previous run of glom), so that you only get statistics for
the most recent lines in the log.  `$LOGFILE$` will be the *local* name of the file;
by default they get copied into `/var/tmp/glom`, which gets created if it doesn't already
exist.

You should call glom every so often with cron, then use a cacti script (which I haven't
written yet) to read from the `results` table.

