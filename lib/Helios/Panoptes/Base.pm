package Helios::Panoptes::Base;

use 5.008;
use strict;
use warnings;
use base qw(CGI::Application);
use Data::Dumper;

use CGI::Application::Plugin::DBH qw(dbh_config dbh);
use Data::ObjectDriver::Driver::DBI;

use Helios::Service;
use Helios::Error;

our $VERSION = '1.51_2830';

our $CONF_PARAMS;
our %FUNCMAPBYID = ();
our %FUNCMAPBYNAME = ();

# date structures
our @MON_LIST   = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
our @MONTH_LIST = qw(January February March April May June July August September October November December);
our @DAY_LIST   = qw(Sun Mon Tue Wed Thu Fri Sat);

# log level structures
our @LOG_LEVEL_LIST = ('EMERG','ALERT','CRIT','ERROR','WARN','NOTICE','INFO','DEBUG');
our %LOG_LEVEL_MAP = (
	'LOG_EMERG'   => 0,
	'LOG_ALERT'   => 1,
	'LOG_CRIT'    => 2,
	'LOG_ERR'     => 3,
	'LOG_WARNING' => 4,
	'LOG_NOTICE'  => 5,
	'LOG_INFO'    => 6,
	'LOG_DEBUG'   => 7
);

=head1 NAME

Helios::Panoptes::Base - base class for Helios::Panoptes applications

=head1 DESCRIPTION

Helios::Panoptes::Base serves as the base class for the different web 
applications that make up Helios::Panoptes.

=head1 CGI::APPLICATION METHODS

=head2 setup()

=cut

sub setup {
	die "NOT IMPLEMENTED";
}


=head2 teardown()

The only thing that currently happens in teardown() is the database is disconnected.

=cut

sub teardown {
	$_[0]->dbh->disconnect();
}

=head1 COMMON METHODS

These methods 

=head2 getConfig()

=cut

sub getConfig { return $CONF_PARAMS; }


=head2 getFuncmapByFuncid()

=cut

sub getFuncmapByFuncid {
	my $self = shift;
	if (keys %FUNCMAPBYID) { return %FUNCMAPBYID; }
	my $dbh = $self->dbh();

	my $sth = $dbh->prepare_cached("SELECT funcid, funcname FROM funcmap");
	$sth->execute();
	my $rs = $sth->fetchall_arrayref();
	$sth->finish();
	
	foreach (@$rs) {
		$FUNCMAPBYID{$_->[0]} = $_->[1];
	}
	
	return %FUNCMAPBYID;
}

=head2 getFuncmapByFuncname()

=cut

sub getFuncmapByFuncname {
	my $self = shift;
	if (keys %FUNCMAPBYNAME) { return %FUNCMAPBYNAME; }
	my $dbh = $self->dbh();

	my $sth = $dbh->prepare_cached("SELECT funcname, funcid FROM funcmap");
	$sth->execute();
	my $rs = $sth->fetchall_arrayref();
	$sth->finish();
	
	foreach (@$rs) {
		$FUNCMAPBYNAME{$_->[0]} = $_->[1];
	}
	
	return %FUNCMAPBYNAME;
}


=head2 getLogLevelList()

=head2 getLogLevelMap()

=cut

sub getLogLevelList { return @LOG_LEVEL_LIST; }
sub getLogLevelMap  { return %LOG_LEVEL_MAP;  }


=head2 initDriver()

=cut

sub initDriver {
	my $self = shift;
	my $config = $self->getConfig();
	my $driver = Data::ObjectDriver::Driver::DBI->new(
	    dsn      => $config->{dsn},
	    username => $config->{user},
	    password => $config->{password}
	);	
	return $driver;	
}


=head2 parseEpochDate($epoch_seconds)

Given a time in epoch seconds, parseEpochDate() returns a hashref containing 
the component date parts of the date on the Greogorian calendar:

 yyyy  four-digit year
 mm    two-digit month
 mon   3-letter month
 month Month full name
 day   3-letter day of week
 ddd   3-digit day of year
 dd    two-digit day of month
 hh    twenty-four hour 
 mi    two-digit minutes
 ss    two-digit seconds

=cut

sub parseEpochDate {
	my $self = shift;
	my $e = shift;
	my $dhash;
	my @p = localtime($e);
	$dhash->{ss}    = sprintf("%02d", $p[0]);
	$dhash->{mi}    = sprintf("%02d", $p[1]);
	$dhash->{hh}    = sprintf("%02d", $p[2]);
	$dhash->{dd}    = sprintf("%02d", $p[3]);
	$dhash->{mm}    = sprintf("%02d", $p[4] + 1);
	$dhash->{mon}   = $MON_LIST[ $p[4] ];
	$dhash->{month} = $MONTH_LIST[ $p[4] ];
	$dhash->{yyyy}  = sprintf("%04d", $p[5] + 1900);
	$dhash->{day}   = $DAY_LIST[ $p[6] ];
	$dhash->{ddd}   = sprintf("%03d", $p[7] + 1);

	return $dhash;
}


# BEGIN CODE Copyright (C) 2008-9 by CEB Toolbox, Inc.

# These methods have been modified from the original code extracted from 
# Helios::Panoptes 1.44 to better fit operation in H::P 1.5x. 

=head2 parseConfig()

=cut

sub parseConfig {
	my $self = shift;
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
	return $CONF_PARAMS;
}

=head2 parseAllConfigParams([$group_by_field])

Returns a hashref data structure containing all of the config params for all of 
the services in the Helios collective database.  The $group_by_field can be 
either 'service' or 'host' ('service' is the default).

=cut

sub parseAllConfigParams {
	my $self = shift;
	my $group_by_field = @_ ? shift : 'service';
	my $dbh = $self->dbh();
	my $order_by_field;
	my $order_by_field2;
	my $config;

	if ($group_by_field eq 'service') {
		$order_by_field  = 'worker_class';
		$order_by_field2 = 'host';
	} else {
		$order_by_field  = 'host';
		$order_by_field2 = 'worker_class';
	}

	my $sql = "SELECT $order_by_field, $order_by_field2, param, value FROM helios_params_tb ORDER BY $order_by_field, $order_by_field2";
	my $sth = $dbh->prepare_cached($sql);
	$sth->execute();
	my $rs = $sth->fetchall_arrayref();
	$sth->finish();
	
	foreach (@$rs) {
		$config->{ $_->[0] }->{ $_->[1] }->{ $_->[2] } = $_->[3];
	}

	return $config;
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
		if ($action eq 'del') {
			$sql = 'DELETE FROM helios_params_tb WHERE host = ? AND worker_class = ? AND param = ?';
			$dbh->do($sql, undef, $host, $worker_class, $param) or throw Error::Simple('modParam delete FAILURE: '.$dbh->errstr);
			last SWITCH;
		}
		if ($action eq 'mod') {
			$self->modParam('del', $worker_class, $host, $param);
			$self->modParam('add', $worker_class, $host, $param, $value);
			last SWITCH;
		}
		throw Error::Simple("modParam invalid action: $action");
	}

	return 1;
}


# END CODE Copyright CEB Toolbox, Inc.



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
