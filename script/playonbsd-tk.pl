#!/usr/bin/env perl
use strict;
use warnings;
use feature 'unicode_strings';

use FindBin;
use lib "$FindBin::Bin/../lib";

use Tkx;		# package p5-Tkx
foreach my $elem (1, 2, 3, 4, 5) {
	Tkx::button(".b$elem",
		-text => "Hello, world -$elem",
		-command => sub { Tkx::destroy("."); },
	);
	Tkx::pack(".b$elem");
}

Tkx::MainLoop();
