package Helios::Panoptes::JobLog;

use 5.008;
use strict;
use warnings;
use base qw(CGI::Application);
use Data::Dumper;

use CGI::Application::Plugin::DBH qw(dbh_config dbh);
use Data::ObjectDriver::Driver::DBI;

use Helios::Service;
use Helios::Error;
use Helios::LogEntry::Levels ':all';

our $VERSION = '1.50_2631';

our $CONF_PARAMS;
our @LOG_PRIORITIES = ('LOG_EMERG','LOG_ALERT','LOG_CRIT','LOG_ERR','LOG_WARNING','LOG_NOTICE','LOG_INFO','LOG_DEBUG');
our %FUNCMAP = ();

=head1 NAME

Helios::Panoptes::JobLog - Helios::Panoptes app providing Job Log view

=head1 DESCRIPTION

Helios::Panoptes::JobLog handles the display for the Panoptes Job Log.

=cut

sub setup {
	my $self = shift;
	$self->start_mode('job_log');
	$self->mode_param('rm');
	$self->run_modes(
		job_log => 'rm_job_log'
	);

	my $inifile;
	if (defined($ENV{HELIOS_INI}) ) {
		$inifile = $ENV{HELIOS_INI};
	} else {
		$inifile = './helios.ini';
	}
	$self->{service} = Helios::Service->new();
	$self->{service}->prep();
	my $config = $self->{service}->getConfig();
	$CONF_PARAMS = $config;

	# connect to db 
# This section of the software is Copyright (C) 2011 by Andrew Johnson.
# See copyright notice at the end of this file for license information.
	# we need to support db options here too
	my $optext = $config->{options};
	my $dbopt = eval "{ $optext }";
	if ($@) {
		# we're just going to log a warning and ignore the option
		$self->{service}->logMsg(LOG_WARNING, __PACKAGE__.': Invalid options specified in config: '.$optext);
		$dbopt = undef;
	}
# End code under Andrew Johnson copyright.
	$self->dbh_config($config->{dsn},$config->{user},$config->{password}, {RaiseError => 1, AutoCommit => 1} );
}


=head2 teardown()

The only thing that currently happens in teardown() is the database is disconnected.

=cut

sub teardown {
	$_[0]->dbh->disconnect();
}



=head1 RUN MODES


=head2 rm_job_log()

The rm_job_log() method handles the display of the Job Log page.

=cut

sub rm_job_log {
	my $self = shift;
	my $dbh = $self->dbh();
	my $q = $self->query();
	my %funcmap = $self->getFuncmap();
	my %jobinfo;
	my @errorinfo;
	my @loginfo;
	my @jobhistory;
	
	my $jobid;
	if ( defined($q->param('jobid')) ) { $jobid = $q->param('jobid'); }
	unless ( defined($jobid) ) {
		Helios::Error::InvalidArg->throw('The jobid parameter is required.');
	}	

	# JOB
=bad
	my $jobtb_sql = qq{ SELECT funcid, insert_time, run_after, grabbed_until, arg FROM job WHERE jobid = ? };
	my $jobtb_sth = $dbh->prepare_cached($jobtb_sql);
	$jobtb_sth->execute($jobid);
	my $jobtb_rs = $jobtb_sth->fetchrow_arrayref();
	$jobtb_sth->finish();
	$jobinfo{jobid}         = $jobid;
	$jobinfo{service_name}  = $funcmap{ $jobtb_rs->[0] };
	$jobinfo{insert_time}   = $jobtb_rs->[1] ? scalar localtime($jobtb_rs->[1]) : undef;
	$jobinfo{run_after}     = $jobtb_rs->[2] ? scalar localtime($jobtb_rs->[2]) : undef;
	$jobinfo{grabbed_until} = $jobtb_rs->[3] ? scalar localtime($jobtb_rs->[3]) : undef;
	$jobinfo{arg}           = $jobtb_rs->[4];
=cut
	$jobinfo{jobid} = $jobid;
	my $drvr = $self->initDriver();
	my $sj = $drvr->lookup('TheSchwartz::Job' => $jobid);
	if ( defined($sj) ) {
		$jobinfo{service_name}  = $funcmap{ $sj->funcid };
		$jobinfo{insert_time}   = scalar localtime($sj->insert_time);
		$jobinfo{run_after}     = scalar localtime($sj->run_after);
		$jobinfo{grabbed_until} = scalar localtime($sj->grabbed_until);
		$jobinfo{arg}           = $sj->arg()->[0];
	}

	# ERROR
	my $errtb_sql = qq{ SELECT funcid, error_time, message FROM error WHERE jobid = ? ORDER BY error_time DESC };
	my $errtb_sth = $dbh->prepare_cached($errtb_sql);
	$errtb_sth->execute($jobid);
	my $errtb_rs = $errtb_sth->fetchall_arrayref();
	$errtb_sth->finish();
	foreach (@$errtb_rs) {
		my %err;
		$err{funcname}   = $funcmap{ $_->[1] };
		$err{error_time} = scalar localtime($_->[0]);
		$err{message}    = $_->[2];
		push(@errorinfo, \%err);
	}
	
	# HELIOS_JOB_HISTORY_TB
	my $jhtb_sql = qq{ SELECT funcid, insert_time, run_after, grabbed_until, complete_time, exitstatus, arg FROM helios_job_history_tb WHERE jobid = ? ORDER BY complete_time DESC };
	my $jhtb_sth = $dbh->prepare_cached($jhtb_sql);
	$jhtb_sth->execute($jobid);
	my $jhtb_rs = $jhtb_sth->fetchall_arrayref();
	$jhtb_sth->finish();
	foreach (@$jhtb_rs) {
		my %hist;
		$hist{funcname}      = $funcmap{ $_->[0] };
		$hist{insert_time}   = scalar localtime($_->[1]);
		$hist{run_after}     = scalar localtime($_->[2]);
		$hist{grabbed_until} = scalar localtime($_->[3]);
		$hist{complete_time} = scalar localtime($_->[4]);
		$hist{exitstatus}    = $_->[5];
		$hist{arg}           = $_->[6];
		push(@jobhistory, \%hist);
	}
	# fill in info from job history if the job isn't in the queue
	unless ($jobinfo{insert_time}) {
		$jobinfo{service_name}  = $jobhistory[0]->{funcname};
		$jobinfo{insert_time}   = $jobhistory[0]->{insert_time};
		$jobinfo{run_after}     = $jobhistory[0]->{run_after};
		$jobinfo{grabbed_until} = $jobhistory[0]->{grabbed_until};
		$jobinfo{arg}           = $jobhistory[0]->{arg};		
	}
	
	
	# HELIOS_LOG_TB
	my $ltb_sql = qq{ SELECT log_time, host, process_id, funcid, job_class, priority, message FROM helios_log_tb WHERE jobid = ? ORDER BY log_time DESC };
	my $ltb_sth = $dbh->prepare_cached($ltb_sql);
	$ltb_sth->execute($jobid);
	my $ltb_rs = $ltb_sth->fetchall_arrayref();
	$ltb_sth->finish();
	foreach(@$ltb_rs) {
		my %log;
		$log{created_at} = scalar localtime($_->[0]);
		$log{host}       = $_->[1];
		$log{process_id} = $_->[2];
		$log{funcid}     = $_->[3];
		$log{job_class}  = $_->[4];
		$log{priority}   = $LOG_PRIORITIES[ $_->[5] ];
		$log{message}    = $_->[6];
		push(@loginfo, \%log);
	}
	
	my $t = $self->load_tmpl('job_log.html', die_on_bad_params => 0, loop_context_vars => 1);
	$t->param(TITLE => "Helios - Job Log " . $jobid);
	$t->param(JOBID => $jobid);
	
	$t->param(JOB_ARG           => $jobinfo{arg});
#	$t->param(JOB_PRIORITY      => $jobinfo{priority});
	$t->param(JOB_INSERT_TIME   => $jobinfo{insert_time});
	$t->param(JOB_RUN_AFTER     => $jobinfo{run_after});
#	$t->param(JOB_COALESCE      => $jobinfo{coalesce});
	$t->param(JOB_SERVICE_NAME  => $jobinfo{service_name});
#	$t->param(JOB_UNIQUE_KEY    => $jobinfo{uniqkey});
	$t->param(JOB_GRABBED_UNTIL => $jobinfo{grabbed_until});

	$t->param(ERROR_ENTRIES     => \@errorinfo);
	$t->param(HISTORY_ENTRIES   => \@jobhistory);
	$t->param(LOG_ENTRIES       => \@loginfo);

	return $t->output();
}

sub getFuncmap {
	my $self = shift;
	if (keys %FUNCMAP) { return %FUNCMAP; }
	my $dbh = $self->dbh();

	my $sth = $dbh->prepare_cached("SELECT funcid, funcname FROM funcmap");
	unless($sth) { throw Error::Simple($dbh->errstr); }
	$sth->execute();

	while (my $r = $sth->fetchrow_arrayref() ) {
		$FUNCMAP{$r->[0]} = $r->[1];
		$FUNCMAP{$r->[1]} = $r->[0];
	}
	$sth->finish();
	
	return %FUNCMAP;
}

sub initDriver {
	my $self = shift;
	my $config = $CONF_PARAMS;
	my $driver = Data::ObjectDriver::Driver::DBI->new(
	    dsn      => $config->{dsn},
	    username => $config->{user},
	    password => $config->{password}
	);	
	return $driver;	
}

1;
__END__

=head1 SEE ALSO

L<Helios::Panoptes>, L<Helios>, L<CGI::Application>

=head1 AUTHOR 

Andrew Johnson, <lajandy at cpan dotorg>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 Logical Helion, LLC.

This library is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself, either Perl version 5.8.0 or, at your option, 
any later version of Perl 5 you may have available.

=head1 WARRANTY 

This software comes with no warranty of any kind.

=cut
