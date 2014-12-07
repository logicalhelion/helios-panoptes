package Helios::Panoptes::SystemLog;

use 5.008008;
use strict;
use warnings;
use parent 'CGI::Application';
use CGI qw(-compile :cgi :form);
use Time::Local;
use Time::Piece;

use Helios::Config;
use Helios::LogEntry::Levels ':all';
use Helios::Error;
use Helios::Service;

our $VERSION = '1.71_0000';

our $Service;
our $Config;

sub setup {
	my $self = shift;
	$self->mode_param('rm');
	$self->run_modes(
		log_view => 'rm_log_view',
	);
	$self->start_mode('log_view');
	$self->error_mode('rm_error');
	
	my $service = Helios::Service->new();
	$service->prep();

	$Service = $service;
	$Config  = $service->getConfig();	
}


=head1 RUN MODE METHODS

=head2 rm_log_view()

=cut

sub rm_log_view {
	my $self = shift;
	my $q = $self->query();
	my $config = $Config;
	my $jobtypes_by_id    = $self->get_jobtypes_by_id();
#[]	my $jobtypes_by_name  = $self->get_jobtypes_by_name();
	my $log_levels_by_id   = $self->get_log_levels_by_id();
#[]	my $log_levels_by_name = $self->get_loglevels_by_name();
	my $sql;
	my @whereclauses;
	my @plhdrs;
	my @log_entries;
	my $dbh;

	# get the form values
	my @form_priorities   = $q->param('priorities');
	my $form_jobtypeid    = defined($q->param('jobtypeid')) ? $q->param('jobtypeid')  : 0;
	my $form_rpp          = defined($q->param('rpp'))       ? $q->param('rpp')        : 50;
	my $form_host         = defined($q->param('host'))      ? $q->param('host')       :'';
	my $form_jobid        = defined($q->param('jobid'))     ? $q->param('jobid')      :'';
	my $form_pid          = defined($q->param('pid'))       ? $q->param('pid')        :'';
	my $form_message      = defined($q->param('message'))   ? $q->param('message')    :'';
	my $form_date_begin   = defined($q->param('date_begin'))? $q->param('date_begin') :'';
	my $form_date_end     = defined($q->param('date_end'))  ? $q->param('date_end')   :'';
	
	# sanity checks
	if ( $form_jobtypeid =~ /\D/ || length($form_jobtypeid) > 32 ) { $form_jobtypeid = 0; }
	foreach (@form_priorities) {
		if ( $_ =~ /\D/ || $_ < 0 || $_ > 7) { @form_priorities = (); last; }
	} 
	if ( $form_rpp =~ /\D/ ) { $form_rpp = 50; }
	if ( length($form_host) > 128 && $form_host =~ /[^\w\s_\.\-]/ ) { $form_host = ''; }
	if ( length($form_jobid) > 64 || $form_jobid =~ /\D/ ) { $form_jobid = ''; }
	if ( length($form_pid) > 32 || $form_pid =~ /\D/ ) { $form_pid = ''; }
	if ( length($form_message) > 256 || $form_message =~ /[^\w\s\\\/\:\.\-]/ ) { $form_message = ''; }
	if ( length($form_date_begin) > 20 && $form_date_begin !~ /\d{4}\-\d{2}\-\d{2}[ T]\d\d\:\d\d\:\d\d/ ) { $form_date_begin = ''; }
	if ( length($form_date_end) > 20 && $form_date_end !~ /\d{4}\-\d{2}\-\d{2}[ T]\d\d\:\d\d\:\d\d/ ) { $form_date_end = ''; }
	
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

	# WHERE clauses
	# service
	if ( $form_jobtypeid ) {
		push(@whereclauses, 'funcid = ?');
		push(@plhdrs, $form_jobtypeid);
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
		my $epoch_time = $self->convert_iso8601_to_epoch($form_date_begin);
		push(@whereclauses, 'log_time >= ?');
		push(@plhdrs, $epoch_time);
	}
	
	# date_end
	if ( $form_date_end ) {
		my $epoch_time = $self->convert_iso8601_to_epoch($form_date_end);
		push(@whereclauses, 'log_time < ?');
		push(@plhdrs, $epoch_time);
	}

	my $whereclause = '';
	if (@whereclauses) { $whereclause = 'WHERE '.join(' AND ',@whereclauses); }
	my $orderby = 'ORDER BY log_time DESC';
	$sql = join(' ',($selectfrom, $whereclause, $orderby));

	if ( $form_rpp ) {
		if ( $config->{dsn} =~ /^dbi:Oracle:/i ) {
			$sql = "SELECT * FROM (".$sql.") WHERE rownum < $form_rpp";
		} else {
			$sql .= " LIMIT $form_rpp";
		}
	}
#[]t print $q->header('text/plain'); print $sql;		

	##  database query  ##
	$dbh = $Service->dbConnect();
	my $sth = $dbh->prepare_cached($sql);
	$sth->execute(@plhdrs);

	while (my $r = $sth->fetchrow_arrayref() ) {
		my $ltp = localtime($r->[0]);
		push(@log_entries, {
				log_time  => $ltp->ymd.' '.$ltp->hms,
				host      => $r->[1],
				pid       => $r->[2],
				jobid     => $r->[3],
				service   => $r->[5],
				priority  => $log_levels_by_id->{ $r->[6] },
				message   => $r->[7],
			}
		);
	}

	##  regenerate form elements  ##
	my $plabels = $log_levels_by_id;
	my $pvalues = [];
	@$pvalues = sort keys %$log_levels_by_id;
	unshift(@$pvalues, '-1');
	$plabels->{'-1'} = 'All';
	my $priorities_list = $q->scrolling_list(
		'-name'     => 'priorities',
		'-values'   => $pvalues,
		'-labels'   => $plabels,
		'-size'     => 5,
		'-multiple' => 'true',
		'-default'  => \@form_priorities
	);

	my $jlabels = $jobtypes_by_id;
	my $jvalues = [ sort { $jobtypes_by_id->{$a} cmp $jobtypes_by_id->{$b} } keys %$jobtypes_by_id ];
	unshift(@$jvalues, '0');
	$jlabels->{'0'} = 'All';
	my $jobtypes_list = $q->popup_menu(
		-name => 'jobtypeid',
		-values => $jvalues,
		-labels => $jlabels,
		-default => $form_jobtypeid
	);

	my $rpp_list = $q->popup_menu(
		-name => 'rpp',
		-values => [25, 50, 100, 200, 500, 1000, 2000, 5000, 10000],
		-default => $form_rpp
	);

	##  render the template!  ##
	my $t = $self->load_tmpl('system_log.html', 
		die_on_bad_params => 0, 
		loop_context_vars => 1,
		default_escape => 'html',
		cache => 1,
	);
	$t->param(TITLE => 'Helios - System Log');
	$t->param(LOG_ENTRIES => \@log_entries);

	# regenerate the form
	$t->param(
		PRIORITY_LIST => $priorities_list,
		JOBTYPE_LIST  => $jobtypes_list,
		RPP_LIST      => $rpp_list,  
		DATE_BEGIN    => $form_date_begin,
		DATE_END      => $form_date_end,
		HOST          => $form_host,
		JOBID         => $form_jobid,
		PID           => $form_pid,
		MESSAGE       => $form_message,
	);

	return $t->output();		
}


=head2 rm_error($exception)

=cut

sub rm_error {
	my $self = shift;
	my $error = shift;
	my $q = $self->query();
	
	my $t = $self->load_tmpl('error.html', 
		die_on_bad_params => 0,
		default_escape => 'html',
		cache => 1,
	);
	$t->param(TITLE => 'Helios - Error');
	$t->param(ERROR => "$error");
	$t->output();	
}


=head1 OTHER METHODS

=head2 get_jobtypes_by_id()

=cut

sub get_jobtypes_by_id {
	my $self = shift;
	my $s = $Service;
	my $jobtypes = {};
	
	my $dbh = $s->dbConnect();
	my $rs = $dbh->selectall_arrayref("SELECT funcid, funcname FROM funcmap");
	foreach (@$rs) {
		$jobtypes->{ $_->[0] } = $_->[1];
	}
	$jobtypes;
}


=head2 get_log_levels_by_id()

=cut

sub get_log_levels_by_id {
	{
		0 => 'EMERG', 
		1 => 'ALERT', 
		2 => 'CRIT', 
		3 => 'ERR', 
		4 => 'WARNING', 
		5 => 'NOTICE', 
		6 => 'INFO', 
		7 => 'DEBUG', 
	};
}


=head2 convert_iso8601_to_epoch()

=cut

sub convert_iso8601_to_epoch {
	my $self = shift;
	my $iso8601 = shift;
	my ($date, $time) = split(/[ T]/, $iso8601);
	my @datep = split(/\-/, $date);
	my @timep = split(/:/, $time);
	timelocal($timep[2], $timep[1], $timep[0], $datep[2], $datep[1]-1, $datep[0]);
}



1;
__END__

=head1 AUTHOR 

Andrew Johnson, <lajandy at cpan dotorg>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Logical Helion, LLC.

This library is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself, either Perl version 5.8.0 or, at your option, 
any later version of Perl 5 you may have available.

=head1 WARRANTY 

This software comes with no warranty of any kind.

=cut

