#!/usr/bin/env perl

use 5.008008;
use strict;
use warnings;
use CGI qw(-compile :cgi :form);
use CGI::Fast ();

use Helios::Panoptes::SystemLog;

our $VERSION = '1.71_0000';

while ( my $q = CGI::Fast->new() ){
	my $app = Helios::Panoptes::SystemLog->new(
		QUERY     => $q, 
		TMPL_PATH => 'tmpl',
	);   
	$app->run();
}

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

