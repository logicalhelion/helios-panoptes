use 5.008000;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Helios-Panoptes',
    AUTHOR            => 'Andrew Johnson <lajandy at cpan dotcom>',
    ABSTRACT          => 'Web administration interface to Helios distributed job processing system',
    LICENSE           => 'perl',
    VERSION_FROM      => 'lib/Helios/Panoptes.pm', # finds $VERSION
    PREREQ_PM         => { 'CGI::Fast'            => 1.07,
                           'CGI::Application'     => 4.06,
                           'DBD::Mock'            => 0.11,		# needed by CGI::Application::Plugin::DBH
                           'CGI::Application::Plugin::DBH'
                                                  => 4.00,
                           'HTML::Template'       => 2.91,
                           'Helios'               => 2.60,
                           

                         }
);
