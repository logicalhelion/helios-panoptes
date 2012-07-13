package Helios::Panoptes::JobQueue;

use 5.008;
use strict;
use warnings;
use base 'Helios::Panoptes::Base';

use CGI::Application::Plugin::DBH qw(dbh_config dbh);

our $VERSION = '1.51_2830';

sub setup {
	my $self = shift;
	$self->start_mode('dispatcher');
	$self->mode_param('rm');
	$self->run_modes(
		dispatcher        => 'rm_dispatcher',
		job_queue         => 'rm_job_queue',
		job_queue_count   => 'rm_job_queue_count',
		job_history       => 'rm_job_history',
		job_history_count => 'rm_job_history_count'
	);
	my $config = $self->parseConfig();
		
	# connect to db 
	$self->dbh_config($config->{dsn},$config->{user},$config->{password});
}

=head2 rm_dispatcher()

=cut

sub rm_dispatcher {
	my $self = shift;
	my $q = $self->query();
	if ( $q->param('status') eq 'done') {
		if ( $q->param('job_detail') ) {
			return $self->rm_job_history();
		} else {
			return $self->rm_job_history_count();
		}
	} else {
		if ( $q->param('job_detail')  ) {
			return $self->rm_job_queue();
		} else {
			return $self->rm_job_queue_count();
		}
	}
}


=head2 rm_job_queue()

=cut

sub rm_job_queue {
	my $self = shift;
	my $q = $self->query();
	my $job_detail = $q->param('job_detail');

	my $dbh = $self->dbh();
	my $now = time();
	my %funcmap = $self->getFuncmapByFuncid();
	my $output;
	my $sql;
	my @where_clauses;
	my @plhdr_values;

	# defaults

	$sql = <<ACTIVEJOBSQL;
SELECT funcid,
	jobid,
	uniqkey,
	insert_time,
	run_after,
	grabbed_until,
	priority,
	coalesce
FROM 
	job j
ACTIVEJOBSQL

	# form values
	my $form_thorizon = defined($q->param('time')) ? $q->param('time') : 300;
	my $form_status = defined($q->param('status')) ? $q->param('status') : 'run';
	my $form_detail = defined($q->param('job_detail')) ? $q->param('job_detail') : 1;

	# sanity checks
	if ( $form_thorizon =~ /\D/ ) { $form_thorizon = 300; }
	unless ( length($form_status) < 5 && ($form_status eq 'run' || $form_status eq 'wait' || $form_status eq 'done') ) {
		$form_status = 'run';
	}

	SWITCH: {
		if ($form_status eq 'run') { 
			push(@where_clauses,"grabbed_until != 0");
			$form_thorizon = 0;
			last SWITCH;
		}
		if ($form_status eq 'wait') {
			push(@where_clauses,"run_after < ?");
			push(@plhdr_values, $now);
			push(@where_clauses,"grabbed_until < ?");
			push(@plhdr_values, $now);
			last SWITCH;
		}
		$form_thorizon = 0;
	}

	# time horizon filter
#[]?
#	if ( $form_thorizon ) {
#		push(@where_clauses, "run_after > ?");
#		push(@plhdr_values, $now - $form_thorizon);
#	}

	# complete WHERE
	if (scalar(@where_clauses)) {
		$sql .= " WHERE ". join(' AND ',@where_clauses);
	}

	# ORDER BY
	$sql .= " ORDER BY funcid asc, run_after desc";

#t	print $q->header();
#t	print $sql;

	my $sth = $dbh->prepare_cached($sql);
	$sth->execute(@plhdr_values);

# BEGIN CODE Copyright (C) 2008-9 by CEB Toolbox, Inc.

# These methods have been modified from the original code extracted from 
# Helios::Panoptes 1.44 to better fit operation in H::P 1.5x. 

	my @job_types;
	my $job_count = 0;
	my @dbresult;
	my $current_job_class;
	my $first_result = 1;
	my $last_class = undef;
	while ( my $result = $sth->fetchrow_arrayref() ) {
		if ($first_result) {
			$last_class = $result->[0];
			$first_result = 0;
		}
		if ($result->[0] ne $last_class) {
			push(@job_types, $current_job_class);
			undef $current_job_class;
			$last_class = $result->[0];
			$job_count = 0;
		}
		
		my $insert_time   = $self->parseEpochDate($result->[3]);
		my $run_after     = $self->parseEpochDate($result->[4]);
		my $grabbed_until = $self->parseEpochDate($result->[5]);
		$current_job_class->{JOB_CLASS} = $funcmap{$result->[0]};
		$current_job_class->{JOB_COUNT} = ++$job_count;
		push(@{ $current_job_class->{JOBS} }, 
				{	JOBID         => $result->[1],
					UNIQKEY       => $result->[2],
					INSERT_TIME   => $insert_time->{yyyy}  .'-'.$insert_time->{mm}  .'-'.$insert_time->{dd}  .' '.$insert_time->{hh}  .':'.$insert_time->{mi}  .':'.$insert_time->{ss},
					RUN_AFTER     => $run_after->{yyyy}    .'-'.$run_after->{mm}    .'-'.$run_after->{dd}    .' '.$run_after->{hh}    .':'.$run_after->{mi}    .':'.$run_after->{ss},
					GRABBED_UNTIL => $grabbed_until->{yyyy}.'-'.$grabbed_until->{mm}.'-'.$grabbed_until->{dd}.' '.$grabbed_until->{hh}.':'.$grabbed_until->{mi}.':'.$grabbed_until->{ss},
					PRIORITY => $result->[6],
					COALESCE => $result->[7]
				});
	}
	push(@job_types, $current_job_class);

# END CODE Copyright CEB Toolbox, Inc.

	# (re)create form
	my $time_list = $q->popup_menu(
		-name => 'time',
		-values => ['0', '60', '300', '900', '1800', '3600', '7200', '14400', '28800', '57600', '86400', '172800', '259200', '640800'],
		-labels => {
			'0'      => 'All',
			'60'     => '1 Minute',
			'300'    => '5 Minutes', 
			'900'    => '15 Minutes', 
			'1800'   => '30 Minutes', 
			'3600'   => '1 Hour', 
			'7200'   => '2 Hours', 
			'14400'  => '4 Hours', 
			'28800'  => '8 Hours', 
			'57600'  => '16 Hours', 
			'86400'  => '1 Day', 
			'172800' => '2 Days', 
			'259200' => '3 Days', 
			'640800' => '1 Week'
		},
		-default => "$form_thorizon"
	);
	
	my $status_list = $q->popup_menu(
		-name => 'status',
		-values => ['run', 'wait', 'done'],
		-labels => { 'run' => 'Running Jobs', 'wait' => 'Waiting Jobs', 'done' => 'Completed Jobs'},
		-default => $form_status
	);

	my $tmpl = $self->load_tmpl('jobmanager.html', die_on_bad_params => 0);
	$tmpl->param(TITLE => "Helios - Job Queue");
	$tmpl->param(STATUS_LIST => $status_list);
	$tmpl->param(TIME_LIST => $time_list);
	$tmpl->param(JOB_DETAIL_CHECKED => 1);
	$tmpl->param(JOB_CLASSES => \@job_types);
	return $tmpl->output();	
}

=head2 rm_job_queue_count()

This method will handle a job queue view that displays only counts.

=cut

sub rm_job_queue_count {
	my $self = shift;
	my $q = $self->query();
	my $job_status = $q->param('status');

	my $dbh = $self->dbh();
	my $now = time();
	my %funcmap = $self->getFuncmapByFuncid();
	my $output;
	my $sql;
	my @where_clauses;
	my @plhdr_values;

	$sql = "SELECT funcid, count(*) FROM job ";

	my $form_thorizon = defined($q->param('time')) ? $q->param('time') : 300;
	my $form_status = defined($q->param('status')) ? $q->param('status') : 'run';
	my $form_detail = defined($q->param('detail')) ? $q->param('detail') : 0;

	# sanity checks
	if ( $form_thorizon =~ /\D/ ) { $form_thorizon = 300; }
	unless ( length($form_status) < 5 && ($form_status eq 'run' || $form_status eq 'wait' || $form_status eq 'done') ) {
		$form_status = 'run';
	}

	SWITCH: {
		if ($form_status eq 'run') { 
			push(@where_clauses,"grabbed_until != 0");
			$form_thorizon = 0;
			last SWITCH;
		}
		if ($form_status eq 'wait') {
			push(@where_clauses,"run_after < ?");
			push(@plhdr_values, $now);
			push(@where_clauses,"grabbed_until < ?");
			push(@plhdr_values, $now);
			last SWITCH;
		}
		$form_thorizon = 0;
	}

	# time horizon filter
#[]
#	if ( $form_thorizon ) {
#		push(@where_clauses, "run_after > ?");
#		push(@plhdr_values, $now - $form_thorizon);
#	}

	# complete WHERE
	if (scalar(@where_clauses)) {
		$sql .= " WHERE ". join(' AND ',@where_clauses);
	}

	# GROUP BY
	$sql .= " GROUP BY funcid ";
	# ORDER BY
	$sql .= " ORDER BY funcid asc";

#t	print $q->header();
#t	print $sql;

	my $sth = $dbh->prepare_cached($sql);
	$sth->execute(@plhdr_values);

	my @job_types;
	my $job_count = 0;
	my @dbresult;
	my $current_job_class;
	my $first_result = 1;
	my $last_class = undef;
	while ( my $result = $sth->fetchrow_arrayref() ) {
		if ($first_result) {
			$last_class = $result->[0];
			$first_result = 0;
		}
		if ($result->[0] ne $last_class) {
			push(@job_types, $current_job_class);
			undef $current_job_class;
			$last_class = $result->[0];
			$job_count = 0;
		}
		
		$current_job_class->{JOB_CLASS} = $funcmap{$result->[0]};
		$current_job_class->{JOB_COUNT} = $result->[1];
	}
	push(@job_types, $current_job_class);

	# (re)create form
	my $time_list = $q->popup_menu(
		-name => 'time',
		-values => [0, 60, 300, 900, 1800, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 259200, 640800],
		-labels => {
			0      => 'All',
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
	
	my $status_list = $q->popup_menu(
		-name => 'status',
		-values => ['run', 'wait', 'done'],
		-labels => { 'run' => 'Running Jobs', 'wait' => 'Waiting Jobs', 'done' => 'Completed Jobs'},
		-default => $form_status
	);

	my $tmpl = $self->load_tmpl('jobmanager.html', die_on_bad_params => 0);
	$tmpl->param(TITLE => "Helios - Job Queue");
	$tmpl->param(STATUS_LIST => $status_list);
	$tmpl->param(TIME_LIST   => $time_list);
	$tmpl->param(JOB_DETAIL_CHECKED => 0);
	$tmpl->param(JOB_CLASSES => \@job_types);
	return $tmpl->output();	
}




=head2 rm_job_history()

=cut

sub rm_job_history {
	my $self = shift;
	my $q = $self->query();
	my $config = $self->getConfig();
	my $dbh = $self->dbh();
	my $now = time();
	my %funcmap = $self->getFuncmapByFuncid();
	my $job_status;
	my $output;
	my $sql;
	my @where_clauses;

	my $form_thorizon;

	# this is where it gets tricky...
	if ( $config->{dsn} =~ /\:oracle/i ) {
		# you're using Oracle!  Big collective you've got there!
		# need a consultant to help you out?  Contact me!  :)
		$sql = q{
			SELECT rank, jobid, funcid, run_after, grabbed_until, exitstatus, complete_time
			FROM (
				SELECT 
					jobid,
					funcid,
					run_after,
					grabbed_until,
					exitstatus,
					complete_time,
					RANK() OVER (PARTITION BY jobid ORDER BY complete_time DESC) AS rank
				FROM
					helios_job_history_tb
				WHERE
					complete_time >= ?
				ORDER BY jobid, complete_time DESC
			)
			WHERE rank < 2
			ORDER BY funcid ASC, complete_time DESC
		};
	} else {
		# we'll default to MySQL
	
		$sql = q{
select *
from (select 
      if (@jid = jobid, 
          if (@time = complete_time,
              @rnk := @rnk + least(0,  @inc := @inc + 1),
              @rnk := @rnk + greatest(@inc, @inc := 1)
                           + least(0,  @time := complete_time)
             ),
          @rnk := 1 + least(0, @jid  := jobid) 
                    + least(0, @time :=  complete_time)
                    + least(0, @inc :=  1)
         ) rank,
      jobid,
	  funcid,
	  run_after,
	  grabbed_until,
	  exitstatus,
	  complete_time
      from helios_job_history_tb,
           (select (@jid := 0)) as x
      where complete_time >= ?
      order by jobid, complete_time desc
	 ) as y
where rank < 2
order by funcid asc, complete_time desc
		};
	}

	# form values
	if ( defined($q->param('time')) ) { 
		if ( $q->param('time') =~ /\D/ || !($q->param('time')) ) {
			$form_thorizon = 300;
		} else {
			$form_thorizon = $q->param('time');
		}
	}

	my $sth = $dbh->prepare_cached($sql);
	$sth->execute($now - $form_thorizon);
	
	my @job_types;
	my $job_count = 0;
	my $job_count_failed = 0;
	my @dbresult;
	my $current_job_class;
	my $first_result = 1;
	my $last_class = undef;
	my $last_jobid = 0;
	while ( my $result = $sth->fetchrow_arrayref() ) {
#		print join("|",($result->[0],$result->[1],$result->[2],$result->[3],$result->[4],$result->[5],$result->[6],$result->[7])),"<br>\n";		#p
		if ($first_result) {
			$last_class = $result->[2];
			$first_result = 0;
		}
		if ($result->[2] ne $last_class) {
			push(@job_types, $current_job_class);
			undef $current_job_class;
			$last_class = $result->[2];
			$job_count = 0;
			$job_count_failed = 0;
		}
		
		my $run_after = $self->parseEpochDate($result->[3]);
		my $grabbed_until = $self->parseEpochDate($result->[4]);
		my $complete_time = $self->parseEpochDate($result->[6]);
		$current_job_class->{JOB_CLASS} = $funcmap{$result->[2]};
		$current_job_class->{JOB_COUNT} = ++$job_count;
		if ( $result->[5] != 0 ) { $current_job_class->{JOB_COUNT_FAILED} = ++$job_count_failed; }
		# if this jobid is the same as the last, that means it was a failure that was retried
		# dump it, because we've already added the final completion of the job (whether success or fail)
		# because we sorted "jobid, complete_time desc"
		push(@{ $current_job_class->{JOBS} }, 
				{	JOBID => $result->[1],
					RUN_AFTER     => $run_after->{yyyy}    .'-'.$run_after->{mm}    .'-'.$run_after->{dd}    .' '.$run_after->{hh}    .':'.$run_after->{mi}    .':'.$run_after->{ss},
					GRABBED_UNTIL => $grabbed_until->{yyyy}.'-'.$grabbed_until->{mm}.'-'.$grabbed_until->{dd}.' '.$grabbed_until->{hh}.':'.$grabbed_until->{mi}.':'.$grabbed_until->{ss},
					COMPLETE_TIME => $complete_time->{yyyy}.'-'.$complete_time->{mm}.'-'.$complete_time->{dd}.' '.$complete_time->{hh}.':'.$complete_time->{mi}.':'.$complete_time->{ss},
					EXITSTATUS => $result->[5]
				});
		$last_jobid = $result->[1];
	}
	push(@job_types, $current_job_class);
	@job_types = sort { $a->{JOB_CLASS} cmp $b->{JOB_CLASS} } @job_types;


	# (re)create form
	my $time_list = $q->popup_menu(
		-name => 'time',
		-values => ['0','60', '300', '900', '1800', '3600', '7200', '14400', '28800', '57600', '86400', '172800', '259200', '640800'],
		-labels => {
			'0'      => 'All',
			'60'     => '1 Minute',
			'300'    => '5 Minutes', 
			'900'    => '15 Minutes', 
			'1800'   => '30 Minutes', 
			'3600'   => '1 Hour', 
			'7200'   => '2 Hours', 
			'14400'  => '4 Hours', 
			'28800'  => '8 Hours', 
			'57600'  => '16 Hours', 
			'86400'  => '1 Day', 
			'172800' => '2 Days', 
			'259200' => '3 Days', 
			'640800' => '1 Week'
		},
		-default => '300'
	);
	
	my $status_list = $q->popup_menu(
		-name => 'status',
		-values => ['run', 'wait', 'done'],
		-labels => { 'run' => 'Running Jobs', 'wait' => 'Waiting Jobs', 'done' => 'Completed Jobs'},
		-default => 'done'
	);

#t
#print $q->header('text/plain');
#print $sql,"\n";
#print $form_thorizon,"\n";
#print $time_list,"\n";


	my $tmpl = $self->load_tmpl('jobmanager.html', die_on_bad_params => 0);
	$tmpl->param(TITLE => 'Helios - Job History');
	$tmpl->param(STATUS_LIST => $status_list);
	$tmpl->param(TIME_LIST => $time_list);
	$tmpl->param(JOB_DETAIL_CHECKED => 1);
	$tmpl->param(JOB_CLASSES => \@job_types);
	return $tmpl->output();	
}


=head2 rm_job_history_count()

=cut

sub rm_job_history_count {
	my $self = shift;
	my $q = $self->query;
	my $config = $self->getConfig();
	my $dbh = $self->dbh();
	my $now = time();
	my %funcmap = $self->getFuncmapByFuncid();
	my $job_status;
	my $output;
	my $sql;
	my @where_clauses;

	my $form_thorizon;
	my $form_status;

	if ( $config->{dsn} =~ /\:oracle/i) {
		$sql = q{
			SELECT funcid, exitstatus, count(*)
			FROM (
				SELECT 
					jobid,
					funcid,
					exitstatus,
					complete_time,
					RANK() OVER (PARTITION BY jobid ORDER BY complete_time DESC) AS rank
				FROM
					helios_job_history_tb
				WHERE
					complete_time >= ?
				ORDER BY jobid, complete_time DESC
			)
			WHERE rank < 2
			GROUP BY funcid, exitstatus
		};
	} else {
		# default db is MySQL		

		$sql = q{
select funcid, if(exitstatus,1,0) as exitstatus, count(*) as count
from (select 
      if (@jid = jobid, 
          if (@time = complete_time,
              @rnk := @rnk + least(0,  @inc := @inc + 1),
              @rnk := @rnk + greatest(@inc, @inc := 1)
                           + least(0,  @time := complete_time)
             ),
          @rnk := 1 + least(0, @jid  := jobid) 
                    + least(0, @time :=  complete_time)
                    + least(0, @inc :=  1)
         ) rank,
	  jobid,
	  funcid,
	  run_after,
	  exitstatus,
	  complete_time
      from helios_job_history_tb,
           (select (@jid := 0)) as x
      where complete_time >= ?
      order by jobid, complete_time desc
	 ) as y
where rank < 2
GROUP BY funcid, if(exitstatus,1,0)
		};

	}

	# form values
	if ( defined($q->param('time')) ) { 
		if ( $q->param('time') =~ /\D/ || !($q->param('time')) ) {
			$form_thorizon = 300;
		} else {
			$form_thorizon = $q->param('time');
		}
	}

#t	print $q->header();		
#t	print $sql,"<br>\n";
#t	print $now - $time_horizon,"<br>\n";

	my $sth = $dbh->prepare_cached($sql);
	$sth->execute($now - $form_thorizon);

	my @job_types;
	my $current_funcid;
	my $current_success_jobs = 0;
	my $current_failed_jobs = 0;
	my $last_funcid;
	my $first_result = 1;

	while ( my $result = $sth->fetchrow_arrayref() ) {
#		print join("|",@$result),"<br>\n";		#p
		if ($first_result) {
			$last_funcid = $result->[0];
			$current_funcid = $result->[0];
			$first_result = 0;
		}

		if ($current_funcid ne $result->[0] ) {
			# flush
			push(@job_types, 
				{
				 	JOB_CLASS         => $funcmap{$current_funcid}, 
					JOB_COUNT        => $current_success_jobs + $current_failed_jobs, 
					JOB_COUNT_FAILED =>  $current_failed_jobs
				}
			);
			$last_funcid = $result->[0];
			$current_success_jobs = 0;
			$current_failed_jobs = 0;
		}
		$current_funcid = $result->[0];
		if ($result->[1] == 0) {
			$current_success_jobs = $result->[2];
		} else {
			$current_failed_jobs = $result->[2];
		}
	}
	push(@job_types, 
			{ 
				JOB_CLASS => $funcmap{$current_funcid}, 
				JOB_COUNT => $current_success_jobs + $current_failed_jobs, 
				JOB_COUNT_FAILED =>  $current_failed_jobs
			}
	);
	@job_types = sort { $a->{JOB_CLASS} cmp $b->{JOB_CLASS} } @job_types;

	# (re)create form
	my $time_list = $q->popup_menu(
		-name => 'time',
		-values => [0, 60, 300, 900, 1800, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 259200, 640800],
		-labels => {
			0      => 'All',
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
	
	my $status_list = $q->popup_menu(
		-name => 'status',
		-values => ['run', 'wait', 'done'],
		-labels => { 'run' => 'Running Jobs', 'wait' => 'Waiting Jobs', 'done' => 'Completed Jobs'},
		-default => 'done'
	);

	my $tmpl = $self->load_tmpl('jobmanager.html', die_on_bad_params => 0);
	$tmpl->param(TITLE => 'Helios - Job History');
	$tmpl->param(STATUS_LIST => $status_list);
	$tmpl->param(TIME_LIST => $time_list);
	$tmpl->param(JOB_DETAIL_CHECKED => 0);
	$tmpl->param(JOB_CLASSES => \@job_types);
	return $tmpl->output();	
}



1;
__END__




=head1 SEE ALSO

L<Helios::Service>, L<helios.pl>, <CGI::Application>

=head1 AUTHOR 

Andrew Johnson, <lajandy at cpan dotorg>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Logical Helion, LLC.

Portions of this library, where noted, are 
Copyright (C) 2008-9 by CEB Toolbox, Inc.

This library is free software; you can redistribute it and/or modify it under the same terms as 
Perl itself, either Perl version 5.8.0 or, at your option, any later version of Perl 5 you may 
have available.

=head1 WARRANTY 

This software comes with no warranty of any kind.

=cut
