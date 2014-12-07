use 5.008008;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Helios::Panoptes',
    AUTHOR            => 'Andrew Johnson <lajandy at cpan dotorg>',
    ABSTRACT          => 'Web administration interface to the Helios distributed job processing system',
    LICENSE           => 'perl',
    VERSION_FROM      => 'lib/Helios/Panoptes.pm', # finds $VERSION
    PREREQ_PM         => {
    	                  parent           => 0.221,
                          Helios           => 2.80,
                          CGI::Application => 4.06,
                          HTML::Template   => 2.90,
                          FCGI             => 0.75,		
                          CGI              => 4.09,
                          CGI::Fast        => 2.00,
                          Time::Piece      => 1.12,
                         },
);

# CHANGE HISTORY:
# [LH] [2014-12-06]: Corrected distribution name (double colon, not hyphen).  
# Added CGI, FCGI, CGI::Fast to prereqs needed for new FastCGI support.  Added 
# parent and Time::Piece to prereqs.  Removed Parse::RecDescent,
# HTML::Template::Expr, DBD::Mock, and CGI::Application::Plugin::DBH, since
# they will no longer be needed.  Updated Helios prereq (2.80 or later is now
# required).  Updated Perl version (5.8.8 now required).  Updated author email.
