# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Helios-Panoptes.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 7;
BEGIN { 
	use_ok('Helios::Panoptes'); 
	use_ok('Helios::Panoptes::Base'); 
	use_ok('Helios::Panoptes::CollectiveAdmin'); 
	use_ok('Helios::Panoptes::CtrlPanel'); 
	use_ok('Helios::Panoptes::JobInfo'); 
	use_ok('Helios::Panoptes::JobQueue'); 
	use_ok('Helios::Panoptes::SystemLog'); 

};

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

