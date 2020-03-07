#!/usr/bin/env perl
use strict;
use warnings;

use feature "switch";

# OpenBSD included modules
use Getopt::Std;
use OpenBSD::Pledge;	# OpenBSD::Pledge(3p)
use OpenBSD::Unveil;	# OpenBSD::Unveil(3p)

# from packages
use boolean;		# p5-boolean
#use Text::Table;	# p5-Text-Table

#### possibly useful nuggets ####

# %ENV - environment variables

#### needed variables ####

my $usage = "USAGE: TBD\n";

my @game_table;

my $mode;

my @modes = ("run", "setup", "download", "engine", "detect_engine", "detect_game");

#### Pledge and Unveil ####

# ...

#### functions, subroutines ####
my @modes = ("run", "setup", "download", "engine", "detect_engine", "detect_game");

sub download {
}

sub detect_engine {
}

sub detect_game {
}

sub engine {
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

	# need an uptodate game_table
	update_game_table();

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

# usage: show usage and exit
sub usage {
	print $usage;
	exit;
}

# create_game_table: build the table of games with needed information
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
	# clear anything from the table first
	# ...
}



#### read variables from conf files ####

my %game_engine = readconf("game_engines.conf");

my @games = keys %game_engine;
my @engines = values %game_engine;

#### process arguments ####

my %options=();
getopts("hv", \%options);

my $help = 1 if defined $options{h};
my $verbose = 1 if defined $options{v};

# is specified mode eligible?

$mode = $ARGV[0];

usage() unless defined $mode;

#### main ####

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
