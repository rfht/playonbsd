#!/usr/bin/env perl
use strict;
use warnings;

# OpenBSD included modules
use File::Basename;					# File::Basename(3p)
use Getopt::Std;					# Getopt::Std(3p)
use Getopt::Long;					# Getopt::Long(3p)
use OpenBSD::Pledge;					# OpenBSD::Pledge(3p)
use OpenBSD::Unveil;					# OpenBSD::Unveil(3p)
use Storable qw(lock_nstore lock_retrieve);		# Storable(3p)

# from packages
use boolean;		# p5-boolean

#### possibly useful nuggets ####

# %ENV - environment variables
# $^O - string with name of Operating System
# $0 - name of the perl script as called on command line

#### Dependencies ####
# see above "# from packages"
# sqlite3
# sqlports
# pkg_info

#### Variables ####

my $no_write = 1;	# TODO: remove when ready to test storage; allow use by flag

$Getopt::Std::STANDARD_HELP_VERSION = 1;
my $pob_version = "pre-alpha";
my $usage = "USAGE: TBD\n";

my @game_table;
my $mode;
my @modes = ("run", "setup", "download", "engine", "detect_engine", "detect_game", "uninstall");

# variables for columns in game_table
my $id;			# unique string?
my $name;
my $version;
my $location;		# location (base, ports, home)
my $setup;		# fnaify, hashlink setup...
my $binary;
my $runtime;		# (filename to execute, steamworks-nosteam, other deps)
my $installed;		# store location if installed?
my $duration;		# time played so far
my $last_played;
my $user_rating;
my $not_working;
my $achievements;
my $completed;
my @gt_cols = qw(id name version location setup binary runtime installed duration last_played user_rating not_working achievements completed);

#### Files and Directories ####

my $basename = basename($0);

# directories for playonbsd
my $pobdir = $ENV{"HOME"} . "/.local/share/playonbsd";
my $confdir = $ENV{"HOME"} . "/.config/playonbsd";

# game_table persisten storage
my $game_table_file = $pobdir . "/game_table.nstorable";

# configuration files
my $game_engines_conf = $confdir . "/game_engines.conf";
my $game_binaries_conf = $confdir . "/game_binaries.conf";

#### Pledge and Unveil ####

# if ($^O eq 'OpenBSD') ...
# ...

#### Functions, subroutines ####

sub HELP_MESSAGE {
	print "\n";
	usage();
}

sub VERSION_MESSAGE {
	print "$basename $pob_version\n";
}
	

# create_game_table: create a new game_table
sub create_game_table {

	# games in base install
	my @base_games = `ls /usr/games/`;
	foreach (@base_games) {
		chomp;

		$id = $_ . '-base';
		$name = $_;
		$version = "";
		$location = 'base';
		$setup = "";
		$binary = '/usr/games/' . $_;
		$runtime = "";
		$installed = true;
		$duration = 0;
		$last_played = undef;
		$user_rating = undef;
		$not_working = false;
		$achievements = "";
		$completed = false;

		push_game_table_row();
	}

	# games in ports/packages

	# can only run if sqlports is installed
	unless (-e '/usr/local/share/sqlports') {
		print "Unable to add ports to game_table because sqlports can't be found\n";
	} else {
		# get ports from category games from sqlports
		my @ports_games_unsorted =
			`sqlite3 /usr/local/share/sqlports "select pkgstem from ports where categories like '%games%';"`;
		my @ports_games = sort @ports_games_unsorted;
		undef @ports_games_unsorted;	# free unused variable
		
		# get list of installed packages
		my @installed_packages = `pkg_info -mq`;
		foreach (@ports_games) {
			chomp;

			$id = $_ . '-ports';
			$name = $_;
			$version = "";
			$location = 'ports';
			$setup = "";
			$binary = match_ports_binary($name);
			$runtime = "";
			if (grep /^$name/, @installed_packages) {
				$installed = 1;
			} else {
				$installed = 0;
			}
			$duration = 0;
			$last_played = undef;
			$user_rating = undef;
			$not_working = false;
			$achievements = "";
			$completed = false;

			push_game_table_row();
		}
	}

	# games per playonbsd.com
	# ...

	# games installed, in playonbsd.com (in ~/games/playonbsd for example?)
}

sub download {
}

sub detect_engine {
}

sub detect_game {
}

sub engine {
}

sub find_game_info {
	# parameter: game name, column name
	# potentially unsafe or not working if game name is ambiguous
}

sub find_gameid_info {
	# parameters: game id, column name
	# safer than find_game_info because there shouldn't be ambiguities
}

# init: build a new table of games with needed information
sub init {
	die "init() called with existing game_table_file\n" if -e $game_table_file;
	die "init() called when game_table already defined\n" if @game_table;
	create_game_table();
	write_game_table();
}

sub match_ports_binary {
	shift;
	return '/usr/local/bin/' . $_;
}

sub print_game_table {
	print join "\t", @gt_cols;
	foreach (@game_table) {
		print join "\t", @$_{@gt_cols};
	}
	print scalar @game_table, "\n";
}

sub push_game_table_row {
	push @game_table, {
		id		=> $id,
		name		=> $name,
		version		=> $version,
		location	=> $location,
		setup		=> $setup,
		binary		=> $binary,
		runtime		=> $runtime,
		installed	=> $installed,
		duration	=> $duration,
		last_played	=> $last_played,
		user_rating	=> $user_rating,
		not_working	=> $not_working,
		achievements	=> $achievements,
		completed	=> $completed,
	};
}

# read_game_table_file: read game_table in from $game_table_file
sub read_game_table_file {
	die "game_table object not empty\n" if @game_table;
	@game_table = lock_retrieve($game_table_file) || die "failed to obtain lock and read $game_table_file\n";
}

# readconf: read hashes from file and return hash
sub readconf {
	my $file = $_[0];
	my %retval;

	open(my $in, $file) or die "Can't open $file: $!";
	while (<$in>)
	{
		chomp;
		my ($key, $value) = split /=/;
		next unless defined $value;
		$retval{$key} = $value;
	}
	close $in or die "$in: $!";
	
	return %retval
}

sub run {
	# exit with usage if no argument provided for playonbsd-cli run
	my $run_game = $ARGV[0];
	usage() unless defined $run_game;

	# find the entry matching the game name
	foreach(@game_table) {
		if ($_->{name} eq $run_game) {
			my $start_time = time();
			my $ret = system($_->{binary});
			unless ($ret) {
				my $play_time = time() - $start_time;
				print "time spent in game: ", $play_time, " seconds\n";
				# TODO: save $play_time to database
			}
			last;
		}
	}
	exit;
}

sub setup {
}

# update_game_table: update the database of games and their run info
sub update_game_table {
}

sub uninstall {
}

# usage: show usage and exit
sub usage {
	print $usage;
	exit;
}

sub write_game_table {
	die "game_table not defined; can't write\n" unless @game_table;
	unless ($no_write) {
		lock_nstore \@game_table, $game_table_file || die "failed to obtain lock and store game_table to $game_table_file";
	}
}

sub _execute {
	print "number of arguments: ", scalar @ARGV;
	print "\n";
	print join " ", @ARGV;
	print "\n";
	exit;
	eval $ARGV[1]
}

#### process arguments ####

my %options=();
getopts("hv", \%options);

my $help = 1 if defined $options{h};
my $verbose = 1 if defined $options{v};

# is specified mode eligible?

$mode = $ARGV[0];
shift;				# shorten ARGV now that we have first argument in $mode
usage() unless defined $mode;


#### MAIN ####

# create directories if they don't exist yet
unless (-d $pobdir or mkdir $pobdir) {
	die "Unable to create $pobdir\n";
}
unless (-d $confdir or mkdir $confdir) {
	die "Unable to create $confdir\n";
}

# read config files
my %game_engine = readconf($game_engines_conf) if -e $game_engines_conf;
my %game_binaries = readconf($game_binaries_conf) if -e $game_binaries_conf;

# read or create (bootstrap) the game_table file
if (-e $game_table_file) {
	read_game_table_file();
} else {
	warn "\nWARNING:\ngame_table_file not found. Initialize with '$basename init' or run with '--temp-table' to create a temporary table for the session.\n\n";
}

# determine mode and run subroutine

print "Mode: ", $mode, "\n";

# TODO: sort alphabetically
if	($mode eq 'run')		{ run(); }
elsif	($mode eq 'setup')		{ setup(); }
elsif	($mode eq 'download')		{ download(); }
elsif	($mode eq 'engine')		{ engine (); }
elsif	($mode eq 'detect_engine')	{ detect_engine(); }
elsif	($mode eq 'detect_game')	{ detect_game(); }
elsif	($mode eq 'init')		{ init(); }
elsif	($mode eq '_execute')		{ _execute(); }
else					{ usage(); }
