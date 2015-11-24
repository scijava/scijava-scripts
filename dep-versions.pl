#!/usr/bin/perl

# dep-versions.pl - reports the minimum version of Java
#                   needed for each dependency of a project.

use strict;

my @deps = `mvn dependency:list`;

my $active = 0;
for my $dep (@deps) {
	chomp $dep;

	if (!$active) {
		$active = $dep =~ /The following files have been resolved/;
		next;
	}

	# parse GAPCVS from dependency output
	$dep =~ s/^\[INFO\]\s*//;
	my @t = split(/:/, $dep);
	my $tokens = @t;
	my $g, my $a, my $p, my $c, my $v, my $s;
	if ($tokens == 1) {
		# end of dependencies
		last;
	}
	elsif ($tokens == 5) {
		# e.g.: org.jruby:jruby-core:jar:1.7.12:runtime
		($g, $a, $p, $v, $s) = @t;
		$c = '';
	}
	elsif ($tokens == 6) {
		# e.g.: org.jogamp.jocl:jocl:jar:natives-linux-i586:2.3.2:runtime
		($g, $a, $p, $c, $v, $s) = @t;
	}
	else {
		die "Unknown dependency format: $dep";
	}

	# convert GAPCVS to local repository cache path
	my $gPart = $g;
	$gPart =~ s/\./\//g;
	my $cPart = $c ? "-$c" : '';
	# e.g.: ~/.m2/repository/org/jogamp/jocl/jocl/2.3.2/jocl-2.3.2-natives-linux-i586.jar
	my $path = "\$HOME/.m2/repository/$gPart/$a/$v/$a-$v$cPart.$p";

	# report Java version of the component
	print `class-version.sh "$path"`;
}
