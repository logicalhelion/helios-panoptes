package Helios::Panoptes::JobInfo;

use 5.008;
use strict;
use warnings;
use base qw(Helios::Panoptes::Base);
use Data::Dumper;
use CGI::Application::Plugin::DBH qw(dbh_config dbh);

use Helios::Error;

our $VERSION = '1.51_2820';

=head1 NAME

Helios::Panoptes::JobInfo - Helios::Panoptes app providing Job Info view

=head1 DESCRIPTION

Helios::Panoptes::JobLog handles the display for the Panoptes Job Info.

=head1 CGI::APPLICATION METHODS

=head2 setup()

=cut

sub setup {
	my $self = shift;
	$self->start_mode('jobinfo');
	$self->mode_param('rm');
	$self->run_modes(
		jobinfo => 'rm_jobinfo'
	);

	my $config = $self->parseConfig();

	# connect to db 
	$self->dbh_config($config->{dsn},$config->{user},$config->{password}, {RaiseError => 1, AutoCommit => 1} );
}


=head2 teardown()

The only thing that currently happens in teardown() is the database is disconnected.

=cut

sub teardown {
	$_[0]->dbh->disconnect();
}


=head1 RUN MODES

=head2 rm_jobinfo()

The rm_jobinfo() method handles the display of the Job Log page.

=cut

sub rm_jobinfo {
	my $self = shift;
	my $dbh = $self->dbh();
	my $q = $self->query();
	my %funcmap = $self->getFuncmapByFuncid();
	my @loglevels = $self->getLogLevelList();
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
	$jobinfo{jobid} = $jobid;
	my $drvr = $self->initDriver();
	my $sj = $drvr->lookup('TheSchwartz::Job' => $jobid);
	if ( defined($sj) ) {
		$jobinfo{service_name}  = $funcmap{ $sj->funcid };
		$jobinfo{insert_time}   = defined($sj->insert_time)   ? scalar localtime($sj->insert_time)   : undef;
		$jobinfo{run_after}     = defined($sj->run_after)     ? scalar localtime($sj->run_after)     : undef;
		$jobinfo{grabbed_until} = $sj->grabbed_until ? scalar localtime($sj->grabbed_until) : undef;
		$jobinfo{arg}           = $sj->arg()->[0];
		$jobinfo{uniqkey}       = $sj->uniqkey; 
		$jobinfo{priority}      = $sj->priority;
		$jobinfo{coalesce}      = $sj->coalesce;
	}

	# ERROR
	my $errtb_sql = qq{ SELECT funcid, error_time, message FROM error WHERE jobid = ? ORDER BY error_time DESC };
	my $errtb_sth = $dbh->prepare_cached($errtb_sql);
	$errtb_sth->execute($jobid);
	my $errtb_rs = $errtb_sth->fetchall_arrayref();
	$errtb_sth->finish();
	foreach (@$errtb_rs) {
		my %err;
		$err{funcname}   = $funcmap{ $_->[0] };
		$err{error_time} = scalar localtime($_->[1]);
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
		$log{log_time}   = scalar localtime($_->[0]);
		$log{host}       = $_->[1];
		$log{pid}        = $_->[2];
		$log{funcid}     = $_->[3];
		$log{job_class}  = $_->[4];
		$log{priority}   = $loglevels[ $_->[5] ];
		$log{message}    = $_->[6];
		push(@loginfo, \%log);
	}
	
	my $t = $self->load_tmpl('jobinfo.html', die_on_bad_params => 0, loop_context_vars => 1);
	$t->param(TITLE => "Helios - Job Log " . $jobid);
	$t->param(JOBID => $jobid);
	
	$t->param(JOB_ARG           => $jobinfo{arg});
	$t->param(JOB_INSERT_TIME   => $jobinfo{insert_time});
	$t->param(JOB_RUN_AFTER     => $jobinfo{run_after});
	$t->param(JOB_SERVICE_NAME  => $jobinfo{service_name});
	$t->param(JOB_GRABBED_UNTIL => $jobinfo{grabbed_until});
# these are TheSchwartz::Job features that are technically supported,
# but Helios never actually uses itself. They're left out of the default 
# template theme but could be added if a user needs to customize.
	$t->param(JOB_UNIQUE_KEY    => $jobinfo{uniqkey});
	$t->param(JOB_PRIORITY      => $jobinfo{priority});
	$t->param(JOB_COALESCE      => $jobinfo{coalesce});

	$t->param(ERRORS       => \@errorinfo);
	$t->param(JOB_HISTORY  => \@jobhistory);
	$t->param(LOG_ENTRIES  => \@loginfo);



	return $t->output();
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
