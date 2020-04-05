#!/usr/bin/env perl

use strict;
use warnings;
package PlayOnBSD::Main;

# OpenBSD included modules

#use Encode;		# wide characters in Steam's AppList - encode/decode	# TODO: REALLY NEEDED?
use File::Basename;					# File::Basename(3p)
use File::Path qw(remove_tree);				# File::Path(3p), needed for rmtree
use Getopt::Long qw(:config bundling require_order auto_version auto_help);	# Getopt::Long(3p)
use JSON::PP;						# JSON::PP(3p)
use OpenBSD::Pledge;					# OpenBSD::Pledge(3p)
use OpenBSD::Unveil;					# OpenBSD::Unveil(3p)
use Pod::Usage;						# Pod::Usage(3p)
use Storable qw(lock_nstore lock_retrieve);		# Storable(3p)

# from packages
#use boolean;					# p5-boolean	# TODO: is this really needed??
# TODO: remove Data::Dumper if not needed later!
use Data::Dumper;				# p5-Data-Dumper-Simple-0.11p0
use LWP::Simple;				# p5-libwww	# !! needs p5-LWP-Protocol-https for https !!
#use String::Approx 'amatch';			# p5-String-Approx	# not needed?
use Text::LevenshteinXS qw(distance);		# Text::LevenshteinXS(3p)
use WWW::Form::UrlEncoded qw( build_urlencoded );	# p5-WWW-Form-UrlEncoded, also available as -XS

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
# uname -m
# depotdownloader
# py3-gogrepo
# p5-LWP-Protocol-https
# xdg-utils			# for xdg-open(1)

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
my $arch = `uname -m`;

# Variables for download()
my $download_os = 'linux';
my $force_download;
my $game_name;
my $source = "";

# variables for columns in game_table
my $id;			# unique string?
my $name;
my $version;
my $location;		# location (base, ports, home)
#my @setup;		# fnaify, hashlink setup... # May need to be declared inside the sub instead
#my @binaries;		# May need to be declared inside the sub instead
my $runtime;		# (filename to execute, steamworks-nosteam, other deps)
my $installed;		# store location if installed?
my $duration;		# time played so far
my $last_played;
my $user_rating;
my $not_working;
#my @achievements;	# declare array inside the sub instead
my $completed;
my @gt_cols = qw(id name version location setup binaries runtime installed duration last_played user_rating not_working achievements completed);

#### Files and Directories ####

# directories for playonbsd
my $pobgamedir = $ENV{"HOME"} . "/games/playonbsd";		# TODO: make this configurable
my $pobdatadir = $ENV{"HOME"} . "/.local/share/playonbsd";
my $confdir = $ENV{"HOME"} . "/.config/playonbsd";

# game_table persistent storage
my $game_table_file = $pobdatadir . "/game_table.nstorable";

# configuration files
my $game_engines_conf = $confdir . "/game_engines.conf";
my $game_binaries_conf = $confdir . "/game_binaries.conf";

#### Steam Stuff ####

my $steam_username;						# TODO: read this from a configuration
my $steam_applist = $pobdatadir . "/steam_applist.json";

#### GOG stuff ####

my $gogrepodir = $pobdatadir;

#### PlayOnBSD.com Stuff ####

my $playonbsd_raw = $pobdatadir . "/playonbsd_raw.json";

#### Pledge and Unveil ####

# if ($^O eq 'OpenBSD') ...
# ...

#### Other Configuration ####

binmode(STDOUT, ":utf8");					# so that output e.g. of steam applist is in Unicode

#### Functions, subroutines ####

# create_game_table: create a new game_table
sub create_game_table {
	print "creating game_table\n" if $verbosity > 0;

	# #####################
	# games in base install
	# #####################

	my @base_games = `ls /usr/games/`;
	my @base_binaries = ();
	foreach (@base_games) {
		chomp;

		$id = $_ . '-base';
		$name = $_;
		$version = "";
		$location = 'base';
		my @setup = ();
		@base_binaries = ('/usr/games/' . $_);
		$runtime = "";
		$installed = 1;
		$duration = 0;
		$last_played = 0;
		$user_rating = 0;
		$not_working = 0;
		my @achievements = ();
		$completed = 0;

		push @game_table, {
			id		=> $id,
			name		=> $name,
			version		=> $version,
			location	=> $location,
			setup		=> \@setup,
			binaries	=> \@base_binaries,
			runtime		=> $runtime,
			installed	=> $installed,
			duration	=> $duration,
			last_played	=> $last_played,
			user_rating	=> $user_rating,
			not_working	=> $not_working,
			achievements	=> \@achievements,
			completed	=> $completed,
		};
	}

	# #######################
	# games in ports/packages
	# #######################

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
			"^wtf\$", "^xgolgo\$", "^xlennart\$", "^xroach\$", "^xteddy\$", "^freedoom\$",
			"^freedm\$", "^polymorphable\$"
		);

		# ports that are broken on user's arch
		my @broken_ports = 
			`sqlite3 /usr/local/share/sqlports "SELECT PkgStem FROM Ports INNER JOIN Broken ON Broken.PathId = Ports.PathId WHERE Arch IS NULL OR Arch = '$arch'"`;
		foreach (@broken_ports) {
			push @excl_patterns, "^" . $_ . "\$";
		}

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
			my @binaries = ();

			$name = $_;
			if (grep /^$name/, @installed_packages) {
				$installed = 1;
			} else {
				$installed = 0;
			}

			$id = $_ . '-ports';
			$version = "";
			$location = 'ports';
			my @setup = ();
			@binaries = find_binary_for_port($name);
			@binaries = () unless $binaries[0] and $installed;
			$runtime = "";
			$duration = 0;
			$last_played = 0;
			$user_rating = 0;
			$not_working = 0;
			my @achievements = ();
			$completed = 0;

			push @game_table, {
				id		=> $id,
				name		=> $name,
				version		=> $version,
				location	=> $location,
				setup		=> \@setup,
				binaries	=> \@binaries,
				runtime		=> $runtime,
				installed	=> $installed,
				duration	=> $duration,
				last_played	=> $last_played,
				user_rating	=> $user_rating,
				not_working	=> $not_working,
				achievements	=> \@achievements,
				completed	=> $completed,
			};
		}
	}

	# #######################
	# games per playonbsd.com
	# #######################

	# Download shopping_guide.json if not present		# TODO: change name to playonbsd-games.json or similar
	# TODO: set up criteria for updating the local copy

	my $playonbsd_raw_json;
	unless (-e $playonbsd_raw) {
		$playonbsd_raw_json = get("https://playonbsd.com/raw/shopping_guide.json");	# TODO: replace with variable
		die "ERROR: Couldn't get PlayOnBSD AppList\n" unless defined $playonbsd_raw_json;
		# remove newlines
		$playonbsd_raw_json =~ s/\s*\n\s*//g;	# remove leading, trailing whitespace
		# Store this in playonbsd_raw.json
		print "Downloading PlayOnBSD database\n" if $verbosity > 0;
		open my $filehandle, ">:encoding(UTF-8)", $playonbsd_raw;
		print $filehandle $playonbsd_raw_json;
		close $filehandle;
	} else {
		print "Reading PlayOnBSD database from $playonbsd_raw\n" if $verbosity > 0;
		open(my $in, "<:encoding(UTF-8)", $playonbsd_raw) or die "Can't open $playonbsd_raw: $!";
		$playonbsd_raw_json = <$in>;
		close $in or die "Error closing $in: $!";
	}

	my $playonbsd_json = decode_json $playonbsd_raw_json;
	foreach my $playonbsd_game (@$playonbsd_json) {
		my @setup = ();
		my @binaries = ();

		$id = $playonbsd_game->{'Game'} . '-playonbsd';
		$name = $playonbsd_game->{'Game'};
		$version = "";
		$location = 'playonbsd';
		push @setup, $playonbsd_game->{'Setup'};
		@binaries = ();
		$runtime = "";
		$installed = 0;
		$duration = 0;
		$last_played = 0;
		$user_rating = 0;
		$not_working = 0;
		my @achievements = ();
		$completed = 0;

		push @game_table, {
			id		=> $id,
			name		=> $name,
			version		=> $version,
			location	=> $location,
			setup		=> \@setup,
			binaries	=> \@binaries,
			runtime		=> $runtime,
			installed	=> $installed,
			duration	=> $duration,
			last_played	=> $last_played,
			user_rating	=> $user_rating,
			not_working	=> $not_working,
			achievements	=> \@achievements,
			completed	=> $completed,
		};
	}

	# TODO: sort the table by game name
	# NOT like this: @game_table = sort @game_table;
	print "finished creating game_table\n" if $verbosity > 0;
}

sub download {
	GetOptions (	
		"force|f"	=> \$force_download,
		"os|o=s"	=> \$download_os,
		"source|s=s"	=> \$source
		)
		or pod2usage(2);

	$game_name = $ARGV[0];		# TODO: is this variable really needed here?

	# create $pobgamedir if doesn't exist
	unless ($no_write) {
		unless (-d $pobgamedir or mkdir $pobgamedir) {
			die "ERROR: Unable to create $pobgamedir\n";
		}
	}

	if (lc $source eq lc "Steam") {
		download_steam();
	} elsif (lc $source eq lc "GOG") {
		download_gog();
	} elsif (lc $source eq lc "packages" or lc $source eq lc "package") {
		download_package();
	} elsif ($source eq "") {
		download_autodetect();
	} else {
		die "ERROR: invalid argument for --source|-s\n";
	}
}

sub download_autodetect {
	# autodetect the source based on game_name
}

sub download_gog {
	my $gog_game =		$ARGV[0];
	my $gog_download_os =	'linux';
	my $gog_lang =		'en';

	# is py3-gogrepo available?
	system("which py3-gogrepo >/dev/null 2>&1")
		and die "ERROR: py3-gogrepo not found in PATH\n";

	# go to directory for gogrepo and check that gog-cookies.dat and gog-manifest.dat exist
	chdir $gogrepodir;
	unless (-e 'gog-cookies.dat' and -e 'gog-manifest.dat') {
		die "ERROR: gog-cookies.dat and/or gog-manifest.dat not found in $gogrepodir. Run 'py3-gogrepo login' and 'py3-gogrepo update' in $gogrepodir\n";
	}

	# Convert the game name into a regex
	# TODO: Barony may need a tweak since title is still barony_cursed_edition
	# TODO: Doom 2 may need a tweak; title is doom_ii_master_levels_game
	# 	the_elder_scrolls_iii_morrowind_goty_edition_game
	#	Ion Fury -> ion_maiden_game
	#	Jazz Jackrabbit -> jazz_jackrabbit_collection
	#	Quake -> quake_the_offering_game
	#	Quake 2 -> quake_ii_quad_damage_game
	#	Quake 3 -> quake_iii_arena_and_team_arena
	#	system_shock_classic
	#	tanglewoodr
	my $game_regex = $gog_game;
	$game_regex =~ s/[^a-zA-Z0-9]/.?/g;
	my $gog_titles = `egrep -i \\'title\\'.*$game_regex gog-manifest.dat`;
	die "ERROR: couldn't find matching title in gog-manifest.dat. Do you need to update py3-gogrepo?\n" unless $gog_titles;
	# first try strictest matching, then relax it gradually
	# TODO: add selection from $gog_titles by Levenshtein distance
	$gog_titles =~ /\'($game_regex)\'/i;
	my $match = $1;
	unless ($match) {
		$gog_titles =~ /\'($game_regex[^\']*)/i;
		$match = $1;
	}
	unless ($match) {
		$gog_titles =~ /[^\']*($game_regex[^\']*)/i;
		$match = $1;
	}
	die "ERROR: couldn't find matching title in gog-manifest.dat. Do you need to update py3-gogrepo?\n" unless $match;
	print "Found GOG id match: $match\n";
	
	# TODO: check if game is already installed, if so, error out
	# update entry in gog-manifest.dat for the $gog_download_os
	print "\nUpdating gog-manifest.dat for $gog_game\n";
	system("py3-gogrepo update -id $match -os $gog_download_os -lang $gog_lang") and die "\nError updating gog-manifest.dat for $gog_game\n";

	print "\nDownloading $gog_game from GOG with py3-gogrepo\n" if $verbosity > 0;
	# TODO: add switch to allow not skipping extras
	# TODO: some game content has to come from extras (Tanglewood, Broken Sword 1/2)
	system("py3-gogrepo download -id $match -skipextras $pobgamedir") and die "\nError downloading '$gog_game' with py3-gogrepo\n";

	my $gog_game_dir = $pobgamedir . "/" . $match;
	# identify the archive file
	chdir $gog_game_dir;
	my $gog_download_files = `ls -1`;
	my @gog_files_arr = split(/\n/, $gog_download_files);
	my @gog_sh_files = grep { /.sh$/ } @gog_files_arr;

	# extract the file and discard the archive
	if (scalar @gog_sh_files > 1) {
		die "\nERROR: more than 1 .sh file found. This is not implemented yet.\n";
	} elsif (scalar @gog_sh_files == 1) {
		print "\nExtracting $gog_sh_files[0]\n";
		system("unzip $gog_sh_files[0]");
		unlink $gog_sh_files[0] or warn "WARNING: Could not unlink $gog_sh_files[0]: $!";
		# move files from data/noarch/game into main game directory
		system("mv data/noarch/game/* .") and die "\nERROR while attempting to move files from data/noarch/game\n";
		foreach my $dir ('data', 'meta', 'scripts') {
			remove_tree($dir,
				{ verbose => $verbosity > 0 }
			);
		}
	} else {
		# TODO: look for .exe files then, probably is a windows download
		die "\nERROR: no .sh file found, .exe not implemented yet\n";
	}
}

sub download_package {
	my $pkg_command = "doas pkg_add " . $game_name;
	print "Calling: $pkg_command\n";
	my $ret = system("doas pkg_add $game_name");
	if ($ret > 0) {
		die "\nError downloading '$game_name' with pkg_add(1)\n";
	}
	# TODO: add option to run pkg_add with '-U'???
	# TODO: add a way to obtain required assets for e.g. Barony
}

sub download_steam {
	my $all_steam_apps;		# variable with the raw JSON of all Steam apps
	my $game_dir = $pobgamedir . "/" . $game_name;
	my $preexisting_gamedir;
	my $steam_appid;

	# check if the $game_dir already exists (case-insensitively) and if so,
	#	put it in $preexisting_gamedir
	foreach my $pobgame_subdir (`ls $pobgamedir`) {
		chomp $pobgame_subdir;
		$preexisting_gamedir = $pobgame_subdir if lc $game_name eq lc $pobgame_subdir;
	}
	if ($preexisting_gamedir) {
		$preexisting_gamedir = $pobgamedir . "/" . $preexisting_gamedir;
		die "ERROR: game directory already exists: $preexisting_gamedir\nRun '$basename download [--force|-f] $game_name' to delete and replace the game directory\n"
			unless $force_download and not $no_write;
		print "removing preexisting game dir: $preexisting_gamedir\n"
			if $verbosity > 0;
		remove_tree($preexisting_gamedir,
			{ verbose => $verbosity > 0 }
		);
	}
	# TODO: currently not relevant while it's called directly with mono below
	system("which depotdownloader >/dev/null 2>&1")
		and die "ERROR: depotdownloader not found in PATH\n";

	# TODO: setup how/when to update steam_applist
	if (-e $steam_applist) {
		print "Reading Steam AppList from $steam_applist\n" if $verbosity > 0;
		open(my $in, "<:encoding(UTF-8)", $steam_applist) or die "Can't open $steam_applist: $!";
		$all_steam_apps = <$in>;
		close $in or die "Error closing $in: $!";
	} else {
		# TODO: make this a separate function, store it and only update it periodically
		#	or update it only if game_name can't be found in the list
		$all_steam_apps = get("https://api.steampowered.com/ISteamApps/GetAppList/v0002");
		die "ERROR: Couldn't get Steam AppList\n" unless defined $all_steam_apps;

		# Store this in steam_applist.json
		open my $filehandle, ">:encoding(UTF-8)", $steam_applist;
		print $filehandle $all_steam_apps;
		close $filehandle;
	}

	my $steam_json = decode_json $all_steam_apps;
	foreach my $steam_app (@{ $steam_json->{'applist'}->{'apps'} }) {
		if (lc $steam_app->{'name'} eq lc $game_name) {
			$steam_appid = $steam_app->{'appid'};
			last;
		}
	}
	die "ERROR: Couldn't find AppId for '$game_name'\n" unless $steam_appid;
	print "found AppId: $steam_appid\n" if $verbosity > 0;

	print "Downloading from Steam with depotdownloader ...\n\n";
	# TODO: add a way to have password stored
	my $ret = system("MONO_PATH=/usr/local/share/depotdownloader mono /usr/local/share/depotdownloader/DepotDownloader.dll -dir '$game_dir' -app '$steam_appid' -username $steam_username -os '$download_os'")
		unless $no_write;
	print "\ndepotdownloader return value: $ret\n" if $verbosity > 0;
	die "\nError while downloading from Steam\n" if $ret > 0;		# TODO: add removal of $game_dir if $ret > 0
}

sub detect_engine {
}

sub detect_game {
}

sub engine {
}

sub find_binary_for_port {
	my $port_name = $_[0];
	my @bin_arr = ();

	my @local_binaries = `ls /usr/local/bin`;
	# sanitize filenames
	# TODO: openjkded is not what I'm looking for, but shows up. Should be for optional multiplayer
	# TODO: doesn't pick up corsix-th for corsixth port
	my @false_pos = ( "open", "g", "gls", "ex", "dune", "an", "al", "vacuumdb", "sn",
		"monodocs2slashdoc", "glib-genmarshal", "gtimeout", "firefox",
		"backtrace_test" );
	foreach my $my_bin (@local_binaries) {
		$my_bin =~ tr/A-Za-z0-9._\-//cd;
		undef $my_bin if grep( /^$my_bin$/, @false_pos);
	}
	@local_binaries = grep defined, @local_binaries;	# remove undefs from array
	
	# 1. from stored table (game_binaries.conf)
	# TODO:	use $game_binaries_conf; also put this outside of the loop
	my %gb = readconf('game_binaries.conf');
	foreach my $key (keys %gb) {
		my @bin_array = split ',', $gb{$key};
		s/^\s+// for @bin_array;
		s/\s+$// for @bin_array;
		foreach my $bin_array_element (@bin_array) {
			$bin_array_element = '/usr/local/bin/' . $bin_array_element;
		}
		$gb{$key} = [ @bin_array ];
	}

	if (exists $gb{$port_name}[0]) {
		@bin_arr = @{$gb{$port_name}};
		return @bin_arr;
	}


	# 2. exact match
	foreach my $bin (@local_binaries) {
		if ($port_name eq $bin) {
			$bin_arr[0] = '/usr/local/bin/' . $bin;
			return @bin_arr;
		}
	}
	# 3. case insensitive match (e.g. freedroidRPG, FreeSerf, GMastermind)
	foreach my $bin (@local_binaries) {
		if (lc $port_name eq lc $bin) {
			$bin_arr[0] = '/usr/local/bin/' . $bin;
			return @bin_arr;
		}
	}
	# 4. binary that contains the port's name? (xonotic-sdl, supertux2)
	foreach my $bin (@local_binaries) {
		if (grep(/^$port_name/i, $bin)) {
			$bin_arr[0] = '/usr/local/bin/' . $bin;
			return @bin_arr;
		}
	}
	# 5. binary that is part of the port's name? (e.g. arx, cataclysm (no_x11), quake2 (yquake2))
	foreach my $bin (@local_binaries) {
		if (grep( /^.?$bin/i, $port_name)) {
			$bin_arr[0] = '/usr/local/bin/' . $bin;
			return @bin_arr;
		}
	}
	# 6. Text::LevenshteinXS qw(distance)
	# https://www.perlmonks.org/?node_id=388423
	my @binaries_Levensht = 
		map { $_->[0] }
		sort { $a->[1] <=> $b->[1] }
		map { [ $_, distance($port_name, $_) ] } @local_binaries;
	#print "binary 0: $binaries_Levensht[0]; last binary: $binaries_Levensht[-1]\n";
	$bin_arr[0] = '/usr/local/bin/' . $binaries_Levensht[0];
	# TODO: this will always return a binary. SET A THRESHOLD when an empty one should be returned
	return @bin_arr;
	
	#$bin_arr[0] = "";
	#return \@bin_arr;
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
	print "performing init\n" if $verbosity > 0;
	die "init() called with existing game_table_file\n" if -e $game_table_file;
	die "init() called when game_table already defined\n" if @game_table;
	create_game_table();
	write_game_table();
	print "init completed\n" if $verbosity > 0;
}

sub print_game_table {
	print join "|", @gt_cols;
	print "\n";
	foreach my $row (@game_table) {
		foreach my $element (@$row{@gt_cols}) {
			if (ref($element) eq 'ARRAY') {
				print join ", ", @$element;
				print "|";
			} else {
				print $element, "|";
			}
		}
		print "\n";
		#foreach my $element (@$row) {
			#print $element, "|";
		#}
		#print "\n";
		#print join "|", @$_{@gt_cols};
		#print "\n";
	}
	print scalar @game_table, "\n";
}

# read_game_table_file: read game_table in from $game_table_file
sub read_game_table_file {
	die "game_table object not empty\n" if @game_table;
	@game_table = lock_retrieve($game_table_file) || die "failed to obtain lock and read $game_table_file\n";
}

# readconf: read hashes from file and return hash
sub readconf {
	# parameters:	filename
	my $file = $_[0];
	my %retval;

	open(my $in, $file) or die "Can't open $file: $!";
	while (<$in>)
	{
		chomp;
		my ($key, $value) = split /=/;
		next unless defined $value;
		$key =~ s/^\s+//;
		$key =~ s/\s+$//;
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

	my $binary = find_gamename_info($run_game, 'binaries');
	my $start_time = time();
	my $ret = system($binary);
	unless ($ret) {
		my $play_time = time() - $start_time;
		print "time spent in game: ", $play_time, " seconds\n";
		# TODO: save $play_time to database
	}
	exit;
}

sub select_field {
	# returns value from a specific field in the game table
	#
	# parameters:	patter column name, pattern, return column name
	# return value:	the value in return column name; empty string if not found
	#
	# example: to select only rows with empty binaries column:
	#	./playonbsd-cli.pl -v _execute "select_field('name', '^Timespinner$', 'setup')"
	#
	my $pattern_colname = $_[0];
	my $pattern = $_[1];
	my $ret_colname = $_[2];

	foreach my $tbl_row (@game_table) {
		if ($tbl_row->{$pattern_colname} =~ /$pattern/) {
			return $tbl_row->{$ret_colname};
		}
	}
	return "";
}

sub select_rows {
	# prints rows from the game table, selected by pattern in a column
	#
	# parameters:	column name, pattern
	# return value:	number of matching rows
	#
	# example: to select only rows with empty binaries column:
	#	./playonbsd-cli.pl -v _execute "select_rows('binaries', '^$')"
	#
	my $colname = $_[0];
	my $pattern = $_[1];
	my $matching_rows = 0;

	print join "|", @gt_cols;
	print "\n";
	foreach my $tbl_row (@game_table) {
		if ($tbl_row->{$colname} =~ /$pattern/) {
			print join "|", @$tbl_row{@gt_cols};
			print "\n";
			$matching_rows++
		}
	}
	return $matching_rows;
}

sub select_column {
	# returns all values of a column from the game table that match pattern
	#
	# parameters:	column name, pattern
	# return value:	array of values in the column
	#
	# example: to select only rows with empty binaries column:
	#	./playonbsd-cli.pl -v _execute "select_column('binaries', '.')"
	#
	my $colname = $_[0];
	my $pattern = $_[1];
	my @ret = ();

	foreach my $tbl_row (@game_table) {
		if ($tbl_row->{$colname} =~ /$pattern/) {
			push @ret, $tbl_row->{$colname};
		}
	}
	return @ret;
}

sub setup {
	my $game = $ARGV[0];
	$game = "^" . $game . "\$";	# add beginning and end markers for the regex pattern

	# is this a game that needs setup? (generally a PlayOnBSD game, not base or packages)
	# TODO: currently, parentheses in the game name have to be escaped: Baldur's Gate  \(The Original Saga\)
	my $setup_array = select_field('name', $game, 'setup') || die "game $game not found in database\n";
	print "found @$setup_array[0] for setup of $game\n" if $verbosity > 0;

	# TODO: is the game installed?
	# assume the game is to be found in $pobgamedir

	# TODO: check if the game is in an quirks list

	my @name_list = select_column('name', '.');
	# TODO: make sure that array position 0 is always the relevant one here
	if	(@$setup_array[0] eq 'AGS')		{ die "AGS setup not implemented yet\n"; }
	elsif	(@$setup_array[0] =~ /HTML5/i)		{ die "HTML5 setup not implemented yet\n"; }
	elsif	(@$setup_array[0] eq 'HumblePlay')	{ die "HumblePlay setup not implemented yet\n"; }
	elsif	(@$setup_array[0] eq 'dosbox')		{ die "DosBox setup not implemented yet\n"; }
	elsif	(@$setup_array[0] eq 'fnaify')		{ setup_fnaify(); }
	elsif	(@$setup_array[0] eq 'hashlink')		{ setup_hashlink(); }
	elsif	(@$setup_array[0] eq 'libgdx')		{ setup_libgdx(); }
	elsif	(@$setup_array[0] eq 'lwjgl')		{ setup_lwjgl(); }
	elsif	(@$setup_array[0] =~ /minecraft/i)	{ die "Minecraft setup not implemented yet\n"; }
	elsif	(@$setup_array[0] =~ /ren.?py/i)		{ die "Ren'Py setup not implemented yet\n"; }
	elsif	(@$setup_array[0] eq 'romextract')	{ die "romextract setup not implemented yet\n"; }
	# TODO: corsix-th not found because port is named corsixth
	elsif	(grep( /^@$setup_array[0]$/i, @name_list))	{ die "@$setup_array[0] exists in the list of games; this is not implemented yet\n"; }
	else						{ pod2usage(); }
}

sub setup_fnaify() {
	print "in sub ", (caller(0))[3], ", rest not implemented yet\n";
}

sub setup_hashlink() {
	print "in sub ", (caller(0))[3], "\n" if $verbosity > 0;
	my $game_dir = $pobgamedir . "/" . lc $ARGV[0];		# TODO: return to previous working directory again?
	chdir $game_dir;
	print "deleting *.hdll, *.so, and *.so.* in $game_dir\n" if $verbosity > 0;
	unlink glob "*.hdll";
	unlink glob "*.so";
	unlink glob "*.so.*";
}

sub setup_libgdx() {
	print "in sub ", (caller(0))[3], ", rest not implemented yet\n";
}

sub setup_lwjgl() {
	print "in sub ", (caller(0))[3], ", rest not implemented yet\n";
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
	# playonbsd-cli.pl _execute "find_gameid_info('tetris-base', 'binaries')"
	#print find_gameid_info('tetris-base', 'binaries');
	eval "print 'Return value: ', $to_run";
	print "\n";
}

#### Process CLI Arguments ####

GetOptions (	"help|h|?"		=> \$help,
		"man"			=> \$man,
		"no-write"		=> \$no_write,
		"steam-username=s"	=> \$steam_username,
		"temp-table"		=> \$temp_table,
		"verbose|v+"		=> \$verbosity)
	or pod2usage(2);

###### REMOVE THIS AFTER TESTING TO ALLOW WRITING ######
#$no_write = 1;
#$temp_table = 1;
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
	unless (-d $pobdatadir or mkdir $pobdatadir) {
		die "Unable to create $pobdatadir\n";
	}
	unless (-d $confdir or mkdir $confdir) {
		die "Unable to create $confdir\n";
	}
}

# read config files
my %game_engine = readconf($game_engines_conf) if -e $game_engines_conf;
#my %game_binaries = readconf($game_binaries_conf) if -e $game_binaries_conf;

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
