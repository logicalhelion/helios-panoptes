package Helios::Panoptes::CtrlPanel;

use 5.008;
use strict;
use warnings;
use base qw(Helios::Panoptes::Base);
use Data::Dumper;

our $VERSION = '1.51_3070';

# we have to do setup to establish runmode(s)
sub setup {
	my $self = shift;
	$self->start_mode('ctrlpanel');
	$self->mode_param('rm');
	$self->run_modes(
		ctrlpanel => 'rm_ctrlpanel',
		conf_mod  => 'rm_conf_mod'
	);
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
			$current_host->{SERVICE_CLASS} = $last_class;
			push(@$hosts, $current_host);
			undef $params;
			undef $current_host;
			$last_host = $result->[1];

			$current_class->{HOSTS} = $hosts;
			$current_class->{SERVICE_CLASS} = $last_class;
			push(@$classes, $current_class);
			undef $hosts;
			undef $current_class;
			$last_class = $result->[0];
		}
		if ($result->[1] ne $last_host) {
			$current_host->{PARAMS} = $params;
			$current_host->{HOST} = $last_host;
			$current_host->{SERVICE_CLASS} = $last_class;
			push(@$hosts, $current_host);
			undef $params;
			undef $current_host;
			$last_host = $result->[1];
		}
		
		push(@$params, 
			{
				'service_class' => $result->[0],
				'host'    => $result->[1],
				'param'   => $result->[2],
				'value'   => $result->[3]
			}
		);
	}

	$current_host->{PARAMS} = $params;
	$current_host->{HOST} = $last_host;
	$current_host->{SERVICE_CLASS} = $last_class;
	push(@$hosts, $current_host);

	$current_class->{HOSTS} = $hosts;
	$current_class->{SERVICE_CLASS} = $last_class;
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

	return $self->rm_ctrlpanel();
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

