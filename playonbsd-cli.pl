#!/usr/bin/env perl
use strict;
use warnings;

use feature "switch";

# OpenBSD included modules
use Getopt::Std;
use OpenBSD::Pledge;					# OpenBSD::Pledge(3p)
use OpenBSD::Unveil;					# OpenBSD::Unveil(3p)
use Storable qw(lock_nstore lock_retrieve);		# Storable(3p)

# from packages
use boolean;		# p5-boolean
#use Text::Table;	# p5-Text-Table

#### possibly useful nuggets ####

# %ENV - environment variables

#### needed variables ####

my $usage = "USAGE: TBD\n";
my @game_table;
my $mode;
my @modes = ("run", "setup", "download", "engine", "detect_engine", "detect_game", "uninstall");

#### files and directories ####

# directories for playonbsd
my $pobdir = $ENV{"HOME"} . "/.local/share/playonbsd";
my $confdir = $ENV{"HOME"} . "/.config/playonbsd";

# game_table persisten storage
my $game_table_file = $pobdir . "/game_table.nstorable";

# configuration files
my $game_engines_conf = $confdir . "/game_engines.conf";

#### Pledge and Unveil ####

# ...

#### functions, subroutines ####

# bootstrap_game_table_file: build a new table of games with needed information
sub bootstrap_game_table_file {
	die "bootstrap_game_table_file() called with existing game_table_file\n" if -e $game_table_file;
	die "bootstrap_game_table_file() called when game_table already defined\n" if @game_table;
	create_game_table();
	write_game_table();
}

# create_game_table: create a new game_table
#	game ID (unique string?)
# 	game name
#	game version
#	owned on GOG?
#	owned on Steam?
#	location (base, ports, home)
#	setup (fnaify, hashlink setup...)
#	runtime (filename to execute, steamworks-nosteam, other deps)
#	installed (with location?)
#	time played so far
#	last played
#	rating
#	marked not working
#	achievements
#	completed?
sub create_game_table {

	my $id;
	my $name;
	my $version;
	my $location;
	my $setup;
	my $binary;
	my $runtime;
	my $installed;
	my $duration;
	my $last_played;
	my $user_rating;
	my $not_working;
	my $achievements;
	my $completed;

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

	# games in ports/packages
	# ...

	# games per playonbsd.com
	# ...

	# games installed in base

	# games installed from ports

	# games installed, in playonbsd.com (in ~/games for example?)
}

sub download {
}

sub detect_engine {
}

sub detect_game {
}

sub engine {
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
	usage() unless defined $ARGV[1];

	# find the entry matching the game name
	foreach(@game_table) {
		if ($_->{name} eq $ARGV[1]) {
			my $start_time = time();
			system($_->{binary});
			my $play_time = time() - $start_time;
			print "time spent in game: ", $play_time, " seconds\n";
			# TODO: save $play_time to database
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
	lock_nstore \@game_table, $game_table_file || die "failed to obtain lock and store game_table to $game_table_file";
}

#### process arguments ####

my %options=();
getopts("hv", \%options);

my $help = 1 if defined $options{h};
my $verbose = 1 if defined $options{v};

# is specified mode eligible?

$mode = $ARGV[0];

usage() unless defined $mode;

#### MAIN ####

# create directories if they don't exist yet
unless (-d $pobdir or mkdir $pobdir) {
	die "Unable to create $pobdir\n";
}
unless (-d $confdir or mkdir $confdir) {
	die "Unable to create $confdir\n";
}

if (-e $game_table_file) {
	read_game_table_file();
} else {
	# bootstrap game_table_file if it doesn't exist
	bootstrap_game_table_file();
}

# read config files
my %game_engine = readconf($game_engines_conf) if -e $game_engines_conf;

# determine mode and run subroutine

for ($mode) {
	when (/^run/)		{ run(); }
	when (/^setup/)		{ setup(); }
	when (/^download/)	{ download(); }
	when (/^engine/)	{ engine (); }
	when (/^detect_engine/)	{ detect_engine(); }
	when (/^detect_game/)	{ detect_game(); }
	default			{ usage(); }
}
