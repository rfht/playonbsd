#!/usr/bin/env perl
use strict;
use warnings;

# OpenBSD included modules
use File::Basename;					# File::Basename(3p)
use Getopt::Long qw(:config bundling require_order auto_version auto_help);	# Getopt::Long(3p)
use OpenBSD::Pledge;					# OpenBSD::Pledge(3p)
use OpenBSD::Unveil;					# OpenBSD::Unveil(3p)
use Pod::Usage;						# Pod::Usage(3p)
use Storable qw(lock_nstore lock_retrieve);		# Storable(3p)

# from packages
use boolean;		# p5-boolean	# TODO: is this really needed??

#### possibly useful nuggets ####

# %ENV - environment variables
# $^O - string with name of Operating System
# $0 - name of the perl script as called on command line
# To stop Getopt::Long from processing further arguments, insert a double dash "--" on the command line.

#### Dependencies ####
# see above "# from packages"
# sqlite3
# sqlports
# pkg_info

#### Variables ####

my $basename = basename($0);

$main::VERSION = "pre-alpha";	# used by Getopt::Long for auto_version

# variables changed by command-line arguments
my $help =		0;
my $man =		0;
my $no_write =		0;
my $temp_table =	0;
my $verbosity =		0;

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

# directories for playonbsd
my $pobdir = $ENV{"HOME"} . "/.local/share/playonbsd";
my $confdir = $ENV{"HOME"} . "/.config/playonbsd";

# game_table persistent storage
my $game_table_file = $pobdir . "/game_table.nstorable";

# configuration files
my $game_engines_conf = $confdir . "/game_engines.conf";
my $game_binaries_conf = $confdir . "/game_binaries.conf";

#### Pledge and Unveil ####

# if ($^O eq 'OpenBSD') ...
# ...

#### Functions, subroutines ####

# create_game_table: create a new game_table
sub create_game_table {
	print "creating game_table\n" if $verbosity > 0;

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
		$installed = 1;
		$duration = 0;
		$last_played = 0;
		$user_rating = 0;
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

		# remove duplicate entries in game_table (e.g. tome4)
		my @ports_games_uniq = uniq(@ports_games_unsorted);
		undef @ports_games_unsorted;

		# TODO: read exclusion patterns from file
		# Examples: tuxpaint-config, xonotic-server, vegastrike-music, vegastrike-extra,
		#	uqm-voice, uqm-threedomusic, uqm-remix[1-4], tuxpaint-stamps,
		#	depotdownloader, steamworks-nosteam, fnaify, sdl-jstest, mupen64plus-*,
		#	gtetrinet-themes, gnome-twitch, freeciv-share, eboard-extras,
		#	scummvm-tools, amor (not a game), an (anagram generator),
		#	chroma-enigma (is a level pack), cmatrix (not a game), cowsay
		my @excl_patterns = ( "-data\$", "-server\$", "-music\$", "-config\$", "-extras?\$", "-voice\$",
			"-threedomusic\$", "-content\$", "-remix[0-9]+\$", "-stamps\$", "^depotdownloader\$",
			"^steamworks-nosteam\$", "^fnaify\$", "^sdl-jstest\$", "^mupen64plus-", "^lwjgl\$",
			"^lib(?!eralcrimesquad)", "^hackdata\$", "-themes\$", "^gnome-twitch\$", "-share\$",
			"^allegro\$", "-tools\$", "^openttd-", "^amor\$", "^an\$", "^asciiquarium\$",
			"^chroma-enigma\$", "^cmatrix\$", "^x?cowsay\$", "^doomdata\$", "^duke3ddata\$",
			"^fifengine\$", "^fifechan\$", "^fire\$", "^flatzebra\$", "^fragistics\$",
			"^gti\$", "^hypatia\$", "^godot\$", "^insult\$", "^irrlicht\$", "^kturtle\$",
			"^ktux\$", "^mnemosyne\$", "^mudix\$", "^mvdsv\$", "^newvox\$", "^npcomplete\$",
			"^plib\$", "^py.*-game\$", "^pyganim\$", "^qqwing\$", "^qstat\$", "^rocs\$",
			"^sl\$", "^speyes\$", "^tiled\$", "^uforadiant\$", "-speech\$", "^weland\$",
			"^wtf\$", "^xgolgo\$", "^xlennart\$", "^xroach\$", "^xteddy\$"
		);

		my @ports_games_filtered;
		foreach my $pg (@ports_games_uniq) {
			my $match = 0;
			foreach my $ep (@excl_patterns) {
				$match = 1 if $pg =~ /$ep/;
			}
			push @ports_games_filtered, $pg unless $match;
		}
		undef @ports_games_uniq;

		my @ports_games = sort @ports_games_filtered;
		undef @ports_games_filtered;	# free unused variable
		
		# get list of installed packages
		my @installed_packages = `pkg_info -mq`;
		foreach (@ports_games) {
			chomp;

			$id = $_ . '-ports';
			$name = $_;
			$version = "";
			$location = 'ports';
			$setup = "";
			$binary = find_binary_for_port($name);
			$binary = "" unless $binary;
			$runtime = "";
			if (grep /^$name/, @installed_packages) {
				$installed = 1;
			} else {
				$installed = 0;
			}
			$duration = 0;
			$last_played = 0;
			$user_rating = 0;
			$not_working = false;
			$achievements = "";
			$completed = false;

			push_game_table_row();
		}
	}


	# games per playonbsd.com
	# ...

	# games installed, in playonbsd.com (in ~/games/playonbsd for example?)

	# TODO: sort the table by game name
	# NOT like this: @game_table = sort @game_table;
	print "finished creating game_table\n" if $verbosity > 0;
}

sub download {
}

sub detect_engine {
}

sub detect_game {
}

sub engine {
}

sub find_binary_for_port {
	my $port_name = $_[0];

	my @local_binaries = `ls /usr/local/bin`;
	# sanitize filenames
	# TODO: openjkded is not what I'm looking for, but shows up. Should be for optional multiplayer
	# TODO: don't pick up lincity-ng for lincity port; should be xlincity
	# TODO: doesn't pick up corsix-th for corsixth port
	my @false_pos = ( "open", "g", "gls", "ex", "dune", "an", "al", "vacuumdb", "sn",
		"monodocs2slashdoc", "glib-genmarshal", "gtimeout", "firefox",
		"backtrace_test" );
	foreach my $my_bin (@local_binaries) {
		$my_bin =~ tr/A-Za-z0-9._\-//cd;
		undef $my_bin if grep( /^$my_bin$/, @false_pos);
	}
	@local_binaries = grep defined, @local_binaries;	# remove undefs from array
	
	# 1. is there a binary in /usr/local matching the port's name?
	foreach my $bin (@local_binaries) {
		if (grep( /^$port_name$/i, $bin )) {
			my $retval = '/usr/local/bin/' . $bin;
			return $retval;
		}
	}

	# 2. binary that is part of the port's name? (e.g. arx, cataclysm (no_x11))
	# TODO: refine this to be not as sensitive
	# Some false positives: sn (snipe2d, snes9x), open (openxcom, opentyrian, openttd-*)
	foreach my $bin (@local_binaries) {
		return '/usr/local/bin/' . $bin if grep( /^$bin/i, $port_name);
	}

	# 3. binary that contains the port's name? (xonotic-sdl, supertux2)
	foreach my $bin (@local_binaries) {
		return '/usr/local/bin/' . $bin if grep( /^$port_name/i, $bin);
	}

	# 3.5 binary with significant overlap? (cataclysm-tiles for cataclysm-dda)

	# 4. Text::LevenshteinXS qw(distance)

	# 5. what if multiple results?

	# 6. give up (return empty string)
	# TODO: find better return value (empty string causes problems with print
	return;
}

sub find_gamename_info {
	# parameter: game name, column name
	# potentially unsafe or not working if game name is ambiguous
	my $gamename= $_[0];
	my $colname = $_[1];
	foreach (@game_table) {
		if ($_->{'name'} eq $gamename) {
			#print $_->{$colname}, "\n";
			return $_->{$colname};
			last;
		}
	}
}

sub find_gameid_info {
	# parameters: game id, column name
	# safer than find_gamename_info because there shouldn't be ambiguities
	my $gameid = $_[0];
	my $colname = $_[1];
	foreach (@game_table) {
		if ($_->{'id'} eq $gameid) {
			#print $_->{$colname}, "\n";
			return $_->{$colname};
			last;
		}
	}
}

# init: build a new table of games with needed information
sub init {
	die "init() called with existing game_table_file\n" if -e $game_table_file;
	die "init() called when game_table already defined\n" if @game_table;
	create_game_table();
	write_game_table();
}

sub print_game_table {
	print join "|", @gt_cols;
	print "\n";
	foreach (@game_table) {
		print join "|", @$_{@gt_cols};
		print "\n";
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
	print "run, length of ARGV: ", scalar @ARGV, ", ARGV[0]: ", $ARGV[0], "\n" if $verbosity > 0;
	# exit with pod2usage if no argument provided for playonbsd-cli run
	shift @ARGV;
	my $run_game = $ARGV[0];
	pod2usage() unless defined $run_game;

	my $binary = find_gamename_info($run_game, 'binary');
	my $start_time = time();
	my $ret = system($binary);
	unless ($ret) {
		my $play_time = time() - $start_time;
		print "time spent in game: ", $play_time, " seconds\n";
		# TODO: save $play_time to database
	}
	exit;
}

sub setup {
}

sub uniq {
	my %seen;
	grep !$seen{$_}++, @_;
}

# update_game_table: update the database of games and their run info
sub update_game_table {
}

sub uninstall {
}

sub write_game_table {
	if ($no_write) {
		warn "WARNING: writing disabled (no_write); skipping\n";
		return;
	} else {
		die "game_table not defined; can't write\n" unless @game_table;
		lock_nstore \@game_table, $game_table_file || die "failed to obtain lock and store game_table to $game_table_file";
	}
}

sub _execute {
	shift;
	my $to_run = $ARGV[0];
	print "_execute will run: $to_run\n";
	print "\n";
	# TODO: add input validation to prevent system() and other dangerous operations!
	# call like this from the command line:
	# playonbsd-cli.pl _execute "find_gameid_info('tetris-base', 'binary')"
	#print find_gameid_info('tetris-base', 'binary');
	eval "print 'Return value: ', $to_run";
	print "\n";
}

#### Process CLI Arguments ####

GetOptions (	"help|h|?"	=> \$help,
		"man"		=> \$man,
		"no-write"	=> \$no_write,
		"temp-table"	=> \$temp_table,
		"verbose|v+"	=> \$verbosity)
	or pod2usage(2);

###### REMOVE THIS AFTER TESTING TO ALLOW WRITING ######
$no_write = 1;
$temp_table = 1;
########################################################

if ($help)		{ pod2usage(1) };
if ($man)		{ pod2usage(-exitval => 0, -verbose => 2) };
# $no_write doesn't need to be processed here
if ($temp_table)	{ create_game_table() };
# $verbosity doesn't need to be processed here

#### MAIN ####

$mode = $ARGV[0];
shift;				# shorten ARGV now that we have first argument in $mode
pod2usage() unless defined $mode;

# create directories if they don't exist yet
unless ($no_write) {
	unless (-d $pobdir or mkdir $pobdir) {
		die "Unable to create $pobdir\n";
	}
	unless (-d $confdir or mkdir $confdir) {
		die "Unable to create $confdir\n";
	}
}

# read config files
my %game_engine = readconf($game_engines_conf) if -e $game_engines_conf;
my %game_binaries = readconf($game_binaries_conf) if -e $game_binaries_conf;

# read the game_table file unless already initialized (--temp-table flag)
unless (@game_table) {
	if (-e $game_table_file) {
		read_game_table_file();
	} else {
		warn "\nWARNING:\ngame_table_file not found. Initialize with '$basename init' or run with '--temp-table' to create a temporary table for the session.\n\n";
	}
}

# determine mode and run subroutine

print "Mode: $mode\n\n";

# TODO: sort alphabetically
if	($mode eq 'run')		{ run(); }
elsif	($mode eq 'setup')		{ setup(); }
elsif	($mode eq 'download')		{ download(); }
elsif	($mode eq 'engine')		{ engine (); }
elsif	($mode eq 'detect_engine')	{ detect_engine(); }
elsif	($mode eq 'detect_game')	{ detect_game(); }
elsif	($mode eq 'init')		{ init(); }
elsif	($mode eq '_execute')		{ _execute(); }
else					{ pod2usage(); }

__END__

=head1 NAME

playonbsd-cli - manage games on OpenBSD

=head1 SYNOPSIS

playonbsd-cli [-hv] [-man] [MODE] [...]

Modes:
  help
  init
  install
  run
  setup
  uninstall

=head1 OPTIONS

=over 4

=item B<-h/--help>

This message.

=item B<-v/--version>

Print version string.

=back

=head1 DESCRIPTION

B<This program> provides several modes to set up and run games, and manage your game library.

=cut
