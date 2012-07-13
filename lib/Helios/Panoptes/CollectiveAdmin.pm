package Helios::Panoptes::CollectiveAdmin;

use 5.008;
use strict;
use warnings;
use base 'Helios::Panoptes::Base';

use CGI::Application::Plugin::DBH qw(dbh_config dbh);

our $VERSION = '1.51_2830';

sub setup {
	my $self = shift;
	$self->start_mode('collective');
	$self->mode_param('rm');
	$self->run_modes(
		collective => 'rm_collective',
		conf_mod   => 'rm_conf_mod'
	);
	my $config = $self->parseConfig();
		
	# connect to db 
	$self->dbh_config($config->{dsn},$config->{user},$config->{password});
	
}

=head2 rm_collective()

The rm_collective() run mode provides the Collective Admin display, a list of 
what Helios service daemons are running on the various worker hosts.  
Collective Admin also provides some basic controls for adjusting service 
daemon and worker process parameters.

=cut

sub rm_collective {
	my $self = shift;
	my $q = $self->query();
	if ( defined($q->param('groupby')) && $q->param('groupby') eq 'service') {
		return $self->collective_by_service();		
	} else {
		return $self->collective_by_host();
	}
}


=head2 collective_by_host()

The collective_by_host() method provides the Collective Admin display 
grouped by host.

=cut 

sub collective_by_host {
	my $self = shift;
	my $dbh = $self->dbh();
	my $q = $self->query();
	my $config = $self->parseAllConfigParams('host');
	my $register_interval = $config->{register_interval} ? $config->{register_interval} : 360;

	my $register_threshold = time() - $register_interval;

	my $sql = <<STATUSSQL;
SELECT host, 
	worker_class, 
	worker_version, 
	process_id, 
	register_time,
	start_time
FROM helios_worker_registry_tb
WHERE register_time > ?
ORDER BY host, worker_class
STATUSSQL
	
	my $sth = $dbh->prepare_cached($sql);
	$sth->execute($register_threshold);
	my $rs = $sth->fetchall_arrayref();
	$sth->finish();

	my @collective;
	my @dbresult;
	my $current_host;
	my $first_result = 1;
	my $last_host = undef;
	foreach my $result (@$rs) {
		if ($first_result) {
			$last_host = $result->[0];
			$first_result = 0;
		}
		if ($result->[0] ne $last_host) {
			push(@collective, $current_host);
			undef $current_host;
			$last_host = $result->[0];
		}
		
		my $dhash = $self->parseEpochDate($result->[4]);
		$current_host->{HOST} = $result->[0];

		# calc uptime
		my $uptime_string = '';
		{
			use integer;
			my $uptime = time() - $result->[5];
			my $uptime_days = $uptime/86400;
			my $uptime_hours = ($uptime % 86400)/3600;
			my $uptime_mins = (($uptime % 86400) % 3600)/60;
			if ($uptime_days != 0) { $uptime_string .= $uptime_days.'d '; }
			if ($uptime_hours != 0) { $uptime_string .= $uptime_hours.'h '; }
			if ($uptime_mins != 0) { $uptime_string .= $uptime_mins.'m '; }
		}

		# max_workers
		my $max_workers = 1;
		if ( defined($config->{ $result->[0] }->{ $result->[1] }->{MAX_WORKERS}) ) {
			$max_workers = $config->{ $result->[0] }->{ $result->[1] }->{MAX_WORKERS};
		} 

		# figure out status (normal/overdrive/holding/halting)
		my $status;
		my $halt_status = 0;
		my $hold_status = 0;
		my $overdrive_status = 0;
		if ( (defined( $config->{$result->[0] }->{ $result->[1] }->{OVERDRIVE}) && ($config->{$result->[0] }->{ $result->[1] }->{OVERDRIVE} == 1) ) ||
			(defined( $config->{'*'}->{ $result->[1] }->{OVERDRIVE}) && ($config->{'*'}->{ $result->[1] }->{OVERDRIVE} == 1) ) ) {
			$overdrive_status = 1;
			$status = "Overdrive";
		}
		if ( (defined( $config->{$result->[0] }->{ $result->[1] }->{HOLD}) && ($config->{$result->[0] }->{ $result->[1] }->{HOLD} == 1) ) ||
			(defined( $config->{'*'}->{ $result->[1] }->{HOLD}) && ($config->{'*'}->{ $result->[1] }->{HOLD} == 1) ) ) {
			$hold_status = 1;
			$status = "HOLDING";
		}
		if ( defined( $config->{$result->[0] }->{ $result->[1] }->{HALT}) ||
				defined( $config->{'*'}->{ $result->[1] }->{HALT}) ) {
			$halt_status = 1;
			$status = "HALTING";
		}
		push(@{ $current_host->{SERVICES} }, 
				{	HOST            => $result->[0],
					SERVICE_CLASS   => $result->[1],
					SERVICE_VERSION => $result->[2],
					PROCESS_ID      => $result->[3],
					REGISTER_TIME   => $dhash->{yyyy}.'-'.$dhash->{mm}.'-'.$dhash->{dd}.' '.$dhash->{hh}.':'.$dhash->{mi}.':'.$dhash->{ss},
					UPTIME          => $uptime_string,
					STATUS          => $status,
					MAX_WORKERS     => $max_workers,
					OVERDRIVE       => $overdrive_status,
					HOLDING         => $hold_status,
					HALTING         => $halt_status,
				});
	}
	push(@collective, $current_host);
	
	my $tmpl = $self->load_tmpl('collective_host.html', die_on_bad_params => 0);
	$tmpl->param(TITLE => 'Helios - Collective Admin');
	$tmpl->param(COLLECTIVE => \@collective);
	return $tmpl->output();	
}


=head2 collective_by_service()

The collective_by_service() method provides the Collective Admin display 
grouped by service.

=cut

sub collective_by_service {
	my $self = shift;
	my $dbh = $self->dbh();
	my $q = $self->query();
	my $config = $self->parseAllConfigParams('service');
	my $register_interval = $config->{register_interval} ? $config->{register_interval} : 300;

	my $register_threshold = time() - $register_interval;

	my $sql = <<STATUSSQL;
SELECT worker_class AS service,
	host, 
	worker_version AS version, 
	process_id, 
	register_time,
	start_time
FROM helios_worker_registry_tb
WHERE register_time > ?
ORDER BY service, host
STATUSSQL
	
	my $sth = $dbh->prepare_cached($sql);
	$sth->execute($register_threshold);
	my $rs = $sth->fetchall_arrayref();
	$sth->finish();
	
	my @collective;
	my @dbresult;
	my $current_service;
	my $first_result = 1;
	my $last_service = undef;
#t	print $q->header();		
	foreach my $result (@$rs) {
#t		print join("|", @$result),"<br>\n";		
		if ($first_result) {
			$last_service = $result->[0];
			$first_result = 0;
		}
		if ($result->[0] ne $last_service) {
			push(@collective, $current_service);
			undef $current_service;
			$last_service = $result->[0];
		}
		
		my $dhash = $self->parseEpochDate($result->[4]);
		$current_service->{SERVICE_CLASS} = $result->[0];

		# calc uptime
		my $uptime_string = '';
		{
			use integer;
			my $uptime = time() - $result->[5];
			my $uptime_days = $uptime/86400;
			my $uptime_hours = ($uptime % 86400)/3600;
			my $uptime_mins = (($uptime % 86400) % 3600)/60;
			if ($uptime_days != 0) { $uptime_string .= $uptime_days.'d '; }
			if ($uptime_hours != 0) { $uptime_string .= $uptime_hours.'h '; }
			if ($uptime_mins != 0) { $uptime_string .= $uptime_mins.'m '; }
		}

		# max_workers
		my $max_workers = 1;
		if ( defined($config->{ $result->[0] }->{ '*' }->{MAX_WORKERS}) ) {
			$max_workers = $config->{ $result->[0] }->{ '*' }->{MAX_WORKERS};
		} 
		if ( defined($config->{ $result->[0] }->{ $result->[1] }->{MAX_WORKERS}) ) {
			$max_workers = $config->{ $result->[0] }->{ $result->[1] }->{MAX_WORKERS};
		} 

		# figure out status (normal/overdrive/holding/halting)
		my $status;
		my $halt_status = 0;
		my $hold_status = 0;
		my $overdrive_status = 0;
		# determine overdrive status
		if ( defined($config->{$result->[0]}->{'*'}->{OVERDRIVE}) && ($config->{$result->[0]}->{'*'}->{OVERDRIVE} == 1) ) {
			$overdrive_status = 1;
		}
		if ( defined($config->{$result->[0]}->{$result->[1]}->{OVERDRIVE}) ) {
			$overdrive_status = $config->{$result->[0]}->{$result->[1]}->{OVERDRIVE};
		}

		# determine holding status
		if ( defined($config->{$result->[0]}->{'*'}->{HOLD}) && ($config->{$result->[0]}->{'*'}->{HOLD} == 1) ) {
			$hold_status = 1;
		}
		if ( defined($config->{$result->[0]}->{$result->[1]}->{HOLD}) ) {
			$hold_status = $config->{$result->[0]}->{$result->[1]}->{HOLD};
		}


		# determine halt status; if it's even defined, that means the service instance is HALTing
		if ( defined( $config->{$result->[0] }->{ '*' }->{HALT}) ||
				defined( $config->{$result->[0]}->{ $result->[1] }->{HALT}) ) {
			$halt_status = 1;
			$status = "HALTING";
		}
		push(@{ $current_service->{HOSTS} }, 
				{	HOST            => $result->[1],
					SERVICE_CLASS   => $result->[0],
					SERVICE_VERSION => $result->[2],
					PROCESS_ID      => $result->[3],
					REGISTER_TIME   => $dhash->{yyyy}.'-'.$dhash->{mm}.'-'.$dhash->{dd}.' '.$dhash->{hh}.':'.$dhash->{mi}.':'.$dhash->{ss},
					UPTIME          => $uptime_string,
					STATUS          => $status,
					MAX_WORKERS     => $max_workers,
					OVERDRIVE       => $overdrive_status,
					HOLDING         => $hold_status,
					HALTING         => $halt_status,
				});
	}
	push(@collective, $current_service);
	
	my $tmpl = $self->load_tmpl('collective_service.html', die_on_bad_params => 0);
	$tmpl->param(TITLE => 'Helios - Collective Admin');
	$tmpl->param(COLLECTIVE => \@collective);
	return $tmpl->output();	
}


# BEGIN CODE Copyright (C) 2012 Logical Helion, LLC.

=head2 rm_conf_mod()

=cut

sub rm_conf_mod {
	my $self = shift;
	my $q = $self->query();
	my $dbh = $self->dbh();

	my $service       = $q->param('service');
	my $host          = defined($q->param('host')) ? $q->param('host') : '*';
	my $param_name    = $q->param('param');
	my $param_value   = $q->param('value');
	my $action        = $q->param('action');

	unless ($service && $param_name && defined($param_value) && $action) {
		die("Helios config param modifications require a service, parameter name, value, and action.");
	}
	unless ($action eq 'mod' || $action eq 'add' || $action eq 'del') {
		die("Invalid modParam() action specified (can only be 'add','del','mod')");
	}

	$self->modParam($action, $service, $host, $param_name, $param_value);

	return $self->rm_collective();
}

# END CODE Copyright (C) 2012 Logical Helion, LLC.

1;
__END__


=head1 SEE ALSO

L<Helios::Panoptes>, L<Helios>, <CGI::Application>

=head1 AUTHOR 

Andrew Johnson, <lajandy at cpan dotorg>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-9 by CEB Toolbox, Inc.

Portions of this software, where noted, are Copyright (C) 2012 by Logical Helion, LLC.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself, either Perl version 5.8.0 or, at your option, any later version of Perl 5 you may have available.

=head1 WARRANTY 

This software comes with no warranty of any kind.

=cut




