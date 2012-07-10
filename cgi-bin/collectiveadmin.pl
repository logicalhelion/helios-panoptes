#!/usr/bin/env perl

use 5.008;
use strict;
use warnings;
use CGI::Fast ();

use Helios::Panoptes::CollectiveAdmin;

our $VERSION = '1.51_2820';

while (my $q = new CGI::Fast){
   my $app = Helios::Panoptes::CollectiveAdmin->new(QUERY => $q, TMPL_PATH => 'tmpl');   
   $app->run();
}

=head1 NAME

collectiveadmin.pl  - CGI script to bootstrap Helios::Panoptes::CollectiveAdmin

=head1 DESCRIPTION

The collectiveadmin.pl is the CGI script to bootstrap the 
Helios::Panoptes::CollectiveAdmin webapp.

=head1 SEE ALSO

L<Helios::Panoptes>, L<Helios>, <CGI::Application>

=head1 AUTHOR 

Andrew Johnson, <lajandy at cpan dotorg>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Logical Helion, LLC.

This library is free software; you can redistribute it and/or modify it under the same terms as 
Perl itself, either Perl version 5.8.0 or, at your option, any later version of Perl 5 you may 
have available.

=head1 WARRANTY 

This software comes with no warranty of any kind.

=cut
