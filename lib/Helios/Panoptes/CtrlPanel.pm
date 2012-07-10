package Helios::Panoptes::CtrlPanel;

use 5.008;
use strict;
use warnings;
use base qw(Helios::Panoptes::Base);
use Data::Dumper;

# we have to do setup to establish runmode(s)
sub setup {
	my $self = shift;
	$self->start_mode('ctrlpanel');
	$self->mode_param('rm');
	$self->run_modes(ctrlpanel => 'rm_ctrlpanel');
	my $config = $self->parseConfig();

	# connect to db 
	$self->dbh_config($config->{dsn},$config->{user},$config->{password});
}


=head2 rm_ctrlpanel()

This method controls the rendering of the Ctrl Panel view, used to display 
Helios configuration parameters.  
=cut

sub rm_ctrlpanel {
	my $self = shift;
	my $dbh = $self->dbh();
	my $q = $self->query();

	my $output;

	my $sql = <<PNLSQL;
SELECT worker_class,
	host,
	param,
	value
FROM helios_params_tb
ORDER BY worker_class, host, param
PNLSQL

	my $sth = $dbh->prepare_cached($sql);
	$sth->execute();
	my $rs = $sth->fetchall_arrayref();
	$sth->finish();

	my $classes;
	my $hosts;
	my $params = [];
	my $last_host;
	my $last_class;
	my $current_host;
	my $current_class;
	my $first_result = 1;
	foreach my $result (@$rs) {
		if ($first_result) {
			$last_class = $result->[0];
			$last_host = $result->[1];
			$first_result = 0;
		}
		if ($result->[0] ne $last_class) {
			$current_host->{PARAMS} = $params;
			$current_host->{HOST} = $last_host;
			$current_host->{WORKER_CLASS} = $last_class;
			push(@$hosts, $current_host);
			undef $params;
			undef $current_host;
			$last_host = $result->[1];

			$current_class->{HOSTS} = $hosts;
			$current_class->{WORKER_CLASS} = $last_class;
			push(@$classes, $current_class);
			undef $hosts;
			undef $current_class;
			$last_class = $result->[0];
		}
		if ($result->[1] ne $last_host) {
			$current_host->{PARAMS} = $params;
			$current_host->{HOST} = $last_host;
			$current_host->{WORKER_CLASS} = $last_class;
			push(@$hosts, $current_host);
			undef $params;
			undef $current_host;
			$last_host = $result->[1];
		}
		
		push(@$params, 
			{
				'worker_class' => $result->[0],
				'host'    => $result->[1],
				'param'   => $result->[2],
				'value'   => $result->[3]
			}
		);
	}

	$current_host->{PARAMS} = $params;
	$current_host->{HOST} = $last_host;
	$current_host->{WORKER_CLASS} = $last_class;
	push(@$hosts, $current_host);

	$current_class->{HOSTS} = $hosts;
	$current_class->{WORKER_CLASS} = $last_class;
	push(@$classes, $current_class);

#t
#print $q->header('text/plain');
#print Dumper($classes);
	
	my $tmpl = $self->load_tmpl('ctrl_panel.html', die_on_bad_params => 0);
	$tmpl->param(TITLE => "Helios - Ctrl Panel");

	# only fill in parameters if we actually have some
	if ( $classes->[0]->{HOSTS}->[0]->{HOST} ) {
		$tmpl->param(CLASSES => $classes);
	}
	return $tmpl->output();	
}


=head2 ctrl_panel_mod()

Run mode used to modify Helios config parameters.  Used by ctrl_panel() and collective().

The ctrl_panel_mod run mode uses the following parameters:

=over 4

=item worker_class

The worker (service) class of the changed parameter

=item host

The host of the changed parameter (* for all hosts)

=item param

THe name of the parameter

=item value

The value the parameter should be changed to

=item action

The action (add, modify, delete) to perform.  A delete action will delete the param for the worker 
class and host in question (obviously), add will add it, and modify will replace any existing 
values of the parameter with the new value.

=back

=cut

sub ctrl_panel_mod {
	my $self = shift;
	my $dbh = $self->dbh();
	my $q = $self->query();
	my $return_to = $q->param('return_to');

	my $sql;

	my $worker_class = $q->param('worker_class');
	my $host = $q->param('host');
	my $param = $q->param('param');
	my $value = $q->param('value');
	my $action = $q->param('action');

	unless ($worker_class && $host && $param && $action) {
		throw Error::Simple("Worker class ($worker_class), host ($host), param ($param), and action ($action) required");
	}

	$self->modParam($action, $worker_class, $host, $param, $value);

	if (defined($return_to)) {
		if ( defined($q->param('groupby')) ) { 
			print $q->redirect("./panoptes.pl?rm=$return_to&groupby=".$q->param('groupby')); 
		}
		print $q->redirect("./panoptes.pl?rm=$return_to");
	} else {
		print $q->redirect('./panoptes.pl?rm=ctrl_panel');
	}
	return 1;
}


=head2 modParam($action, $worker_class, $host, $param, [$value])

Modify Helios config parameters.  Used by ctrl_panel() and collective() displays.

Valid values for $action:

=over 4

=item add

Add the given parameter for the given class and host

=item delete

Delete the given parameter for the given class and host

=item modify

Modify the given parameter for the given class and host with a new value.  Effectively the same 
as a delete followed by an add.

=back

Worker class is the name of the class.

Host is the name of the host.  Use '*' to make the parameter global to all instances of the worker 
class.

Returns a true value if successful and throws an Error::Simple exception otherwise.

=cut

sub modParam {
	my $self = shift;
	my $dbh = $self->dbh();
	my $action = shift;
	my $worker_class = shift;
	my $host = shift;
	my $param = shift;
	my $value = shift;
	
	my $sql;

	unless ($worker_class && $host && $param && $action) {
		throw Error::Simple("Worker class ($worker_class), host ($host), param ($param), and action ($action) required");
	}

	SWITCH: {
		if ($action eq 'add') {
			$sql = 'INSERT INTO helios_params_tb (host, worker_class, param, value) VALUES (?,?,?,?)';
			$dbh->do($sql, undef, $host, $worker_class, $param, $value) or throw Error::Simple('modParam add FAILURE: '.$dbh->errstr);
			last SWITCH;
		}
		if ($action eq 'delete') {
			$sql = 'DELETE FROM helios_params_tb WHERE host = ? AND worker_class = ? AND param = ?';
			$dbh->do($sql, undef, $host, $worker_class, $param) or throw Error::Simple('modParam delete FAILURE: '.$dbh->errstr);
			last SWITCH;
		}
		if ($action eq 'modify') {
			$self->modParam('delete', $worker_class, $host, $param);
			$self->modParam('add', $worker_class, $host, $param, $value);
			last SWITCH;
		}
		throw Error::Simple("modParam invalid action: $action");
	}

	return 1;
}




1;
__END__


=head1 SEE ALSO

L<Helios::Panoptes>, L<Helios>, <CGI::Application>

=head1 AUTHOR 

Andrew Johnson, <lajandy at cpan dotorg>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-9 by CEB Toolbox, Inc.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself, either Perl version 5.8.0 or, at your option, any later version of Perl 5 you may have available.

=head1 WARRANTY 

This software comes with no warranty of any kind.

=cut

