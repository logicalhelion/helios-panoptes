package Helios::Panoptes::SystemLog;

use 5.008;
use strict;
use warnings;
use base 'Helios::Panoptes::Base';
use Data::Dumper;

use CGI::Application::Plugin::DBH qw(dbh_config dbh);

our $VERSION = '1.51_4740';

sub setup {
	my $self = shift;
	$self->start_mode('system_log');
	$self->mode_param('rm');
	$self->run_modes(
		system_log   => 'rm_system_log'
	);
	my $config = $self->parseConfig();
		
	# connect to db 
	$self->dbh_config($config->{dsn},$config->{user},$config->{password});
}


=head2 rm_system_log

=cut

sub rm_system_log {
	my $self = shift;
	my $config = $self->getConfig();
	my $dbh = $self->dbh();
	my $q = $self->query();
	my %funcmapbyid = $self->getFuncmapByFuncid();
	my %funcmapbyname = $self->getFuncmapByFuncname();
	my @log_levels = $self->getLogLevelList();
	my %log_level_map = $self->getLogLevelMap();
	my $sql;
	my @whereclauses;
	my @plhdrs;
	my @log_entries;

	# get the form values
	my @form_priorities   = $q->param('priorities');
	my $form_funcid       = defined($q->param('service'))   ? $q->param('service')    : 0;
	my $form_thorizon     = defined($q->param('time'))      ? $q->param('time')       : 300;
	my $form_rpp          = defined($q->param('rpp'))       ? $q->param('rpp')        : 50;
	my $form_host         = defined($q->param('host'))      ? $q->param('host')       :'';
	my $form_jobid        = defined($q->param('jobid'))     ? $q->param('jobid')      :'';
	my $form_pid          = defined($q->param('pid'))       ? $q->param('pid')        :'';
	my $form_message      = defined($q->param('message'))   ? $q->param('message')    :'';
	my $form_date_begin   = defined($q->param('date_begin'))? $q->param('date_begin') :'';
	my $form_date_end     = defined($q->param('date_end'))  ? $q->param('date_end')   :'';

	# sanity checks
	if ( $form_thorizon =~ /\D/ ) { $form_thorizon = 300; }
	if ( $form_funcid =~ /\D/   ) { $form_funcid = 0; }
	foreach (@form_priorities) {
		if ( $_ =~ /\D/ || $_ < 0 || $_ > 7) { @form_priorities = (); last; }
	} 
	if ( $form_rpp =~ /\D/ ) { $form_rpp = 50; }
	if ( length($form_host) > 64 && $form_host =~ /\W/ ) { $form_host = ''; }
	if ( length($form_jobid) > 64 && $form_jobid =~ /\D/ ) { $form_jobid = ''; }
	if ( length($form_pid) > 32 && $form_pid =~ /\D/ ) { $form_pid = ''; }
	if ( length($form_message) > 256 ) { $form_message = ''; }
#[]	if ( length($form_date_begin) > 25 && $form_date_begin =~ /[^\d\:\- ]/ ) { $form_date_begin = ''; }
#[]	if ( length($form_date_end) > 32 && $form_date_end =~ /[^\d\:\- ]/ ) { $form_date_end = ''; }


	my $selectfrom = q{
		SELECT
			log_time,
			host,
			process_id,
			jobid,
			funcid,
			job_class,
			priority,
			message
		FROM
			helios_log_tb
	};
	
	# first WHERE condition:  time horizon
#	push(@whereclauses,'log_time >= ?');
#	push(@plhdrs, time() - $form_thorizon);
	
	# service
	if ( $form_funcid ) {
		push(@whereclauses, 'funcid = ?');
		push(@plhdrs, $form_funcid);
	}
	
	# host
	if ( $form_host ) {
		push(@whereclauses, 'host = ?');
		push(@plhdrs, $form_host);
	}
	
	# jobid
	if ( $form_jobid ) {
		push(@whereclauses, 'jobid = ?');
		push(@plhdrs, $form_jobid);
	}

	# pid
	if ( $form_pid ) {
		push(@whereclauses, 'process_id = ?');
		push(@plhdrs, $form_pid);
	}

	# message
	if ( $form_message ) {
		push(@whereclauses, 'message LIKE ?');
		push(@plhdrs, '%'.$form_message.'%');
	}
	
	# priorities
	if (@form_priorities){
		if (scalar(@form_priorities) > 1) {
			push(@whereclauses, ' priority IN ('.join(',', @form_priorities).')');
		} else {
			push(@whereclauses, 'priority = ?');
			push(@plhdrs, $form_priorities[0]);
		}
	}
	
	# date_begin
	if ( $form_date_begin ) {
		push(@whereclauses, 'log_time >= ?');
		push(@plhdrs, $self->parseDateToEpochSeconds($form_date_begin));
	} else {
		# if we don't have a begin date, default to 5 min
		my $beginsecs = time() - 300;
		my $bd = $self->parseEpochDate($beginsecs);
		$form_date_begin = join('-',($bd->{yyyy},$bd->{mm}, $bd->{dd})).' '.join(':',($bd->{hh}, $bd->{mi}, $bd->{ss}));
		push(@whereclauses, 'log_time >= ?');
		push(@plhdrs, $beginsecs);
	}
	
	# date_end
	if ( $form_date_end ) {
		push(@whereclauses, 'log_time < ?');
		push(@plhdrs, $self->parseDateToEpochSeconds($form_date_end));
	}
		
	my $whereclause = 'WHERE '.join(' AND ',@whereclauses);
	my $orderby = 'ORDER BY log_time DESC';
	$sql = join(' ',($selectfrom, $whereclause, $orderby));

	if ( $form_rpp ) {
		if ( $config->{dsn} =~ /^dbi:Oracle:/i ) {
			$sql = "SELECT * FROM (".$sql.") WHERE rownum < $form_rpp";
		} else {
			$sql .= " LIMIT $form_rpp";
		}
	}

	my $sth = $dbh->prepare_cached($sql);
	$sth->execute(@plhdrs);
	
	while (my $r = $sth->fetchrow_arrayref() ) {
		push(@log_entries, {
				log_time  => scalar(localtime($r->[0])),
				host      => $r->[1],
				pid       => $r->[2],
				jobid     => $r->[3],
				service   => $r->[5],
				priority  => $log_levels[ $r->[6] ],
				message   => $r->[7],
			}
		);
	}

	## (re)generate form ##
	my $plabels = {};
	my $pvalues = [];
#	while (my ($key, $value) = each %log_level_map ) {
#		$plabels->{$value} = $key;
#	}
	%$plabels = map { $log_level_map{$_} => $_ } keys %log_level_map;	
	@$pvalues = sort values %log_level_map;
	unshift(@$pvalues, '-1');
	$plabels->{'-1'} = 'All';
	my $priorities_field = $q->scrolling_list(
		-name => 'priorities',
		-values => $pvalues,
		-labels => $plabels,
		-size => 4,
		-multiple => 'true',
		-default => \@form_priorities
	);
	
	my $slabels = {};
	my $svalues = [];
#[]	%$slabels = map { $funcmapbyname{$_} => $_ } keys %funcmapbyname;
	$slabels = \%funcmapbyid; 
	%$slabels = map { $funcmapbyname{$_} => $_ } keys %funcmapbyname;
#[]	@$svalues = sort values %funcmapbyname;
	@$svalues = map { $funcmapbyname{$_} } sort keys %funcmapbyname;
	unshift(@$svalues, '0');
	$slabels->{'0'} = 'All';
	my $service_list = $q->popup_menu(
		-name => 'service',
		-values => $svalues,
		-labels => $slabels,
		-default => $form_funcid
	);
	
#[]	my $search_field_list = $q->popup_menu(
#		-name => 'search_field',
#		-values => ['host', 'jobid', 'message', 'pid'],
#		-labels => { 'host' => 'Host', 'jobid' => 'Jobid', 'message' => 'Message', 'pid' => 'PID'},
#		-default => $form_search_field
#	);
	
	my $rpp_list = $q->popup_menu(
		-name => 'rpp',
		-values => [25, 50, 100, 200, 500, 1000, 2000, 5000, 10000],
		-default => $form_rpp
	);

	my $time_list = $q->popup_menu(
		-name => 'time',
		-values => [60, 300, 900, 1800, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 259200, 640800],
		-labels => {
			60     => '1 Minute',
			300    => '5 Minutes', 
			900    => '15 Minutes', 
			1800   => '30 Minutes', 
			3600   => '1 Hour', 
			7200   => '2 Hours', 
			14400  => '4 Hours', 
			28800  => '8 Hours', 
			57600  => '16 Hours', 
			86400  => '1 Day', 
			172800 => '2 Days', 
			259200 => '3 Days', 
			640800 => '1 Week'
		},
		-default => $form_thorizon
	);

#t
#print $q->header('text/plain');
#print Dumper($sql);
#print "\n\n";
#print Dumper(@plhdrs);
#print "\n\n";
#print Dumper($slabels);
#print "\n\n";
#print Dumper($svalues);
#print "\n\n";
#print Dumper(@log_entries);

	
	my $tmpl = $self->load_tmpl('systemlog.html', die_on_bad_params => 0, loop_context_vars => 1);
	$tmpl->param(TITLE => "Helios - System Log");
	$tmpl->param(PRIORITY_LIST => $priorities_field);
	$tmpl->param(SERVICE_LIST => $service_list);
	$tmpl->param(HOST => $form_host);
	$tmpl->param(JOBID => $form_jobid);
	$tmpl->param(PID => $form_pid);
	$tmpl->param(MESSAGE => $form_message);
	$tmpl->param(RPP_LIST => $rpp_list);
#	$tmpl->param(TIME_LIST => $time_list);
	$tmpl->param(DATE_BEGIN => $form_date_begin);
	$tmpl->param(DATE_END => $form_date_end);	
	$tmpl->param(LOG_ENTRIES => \@log_entries);

	return $tmpl->output();	
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
