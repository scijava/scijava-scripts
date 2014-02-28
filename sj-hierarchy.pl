#!/usr/bin/perl

#
# sj-hierarchy.pl
#

# Script to print out hierarchy of Maven projects built on pom-scijava.
# Requires XML::Simple to be installed.

# Usage: sj-hierarchy.pl

use strict;
use XML::Simple;

# -- Constants --

my @groupIds = (
	'io.scif',
	'loci',
	'net.imagej',
	'net.imglib2',
	'ome',
	'org.scijava',
	'sc.fiji',
);

my $home = $ENV{"HOME"};
my $dir = `dirname "$0"`;
chop $dir;

my %blacklist;
my %versions;
my %pomXML;
my %pomTree;

# -- Main --

{
	my $doList;
	my $doSCM;
	my $doStats;
	my $doTree;

	for my $cmd (@ARGV) {
		if ($cmd =~ /^-\w+$/) {
			for my $c (split(//, $cmd)) {
				if ($c eq 'g') { $doSCM = 1; }
				elsif ($c eq 'l') { $doList = 1; }
				elsif ($c eq 's') { $doStats = 1; }
				elsif ($c eq 't') { $doTree = 1; }
			}
		}
		elsif ($cmd eq '--list') { $doList = 1; }
		elsif ($cmd eq '--scm') { $doSCM = 1; }
		elsif ($cmd eq '--stats') { $doStats = 1; }
		elsif ($cmd eq '--tree') { $doTree = 1; }
	}

	parse_blacklist();
	resolve_artifacts($doList);

	if ($doTree) {
		build_tree();
		dump_tree("org.scijava:pom-scijava", 0);
	}
	if ($doSCM) {
		list_scms();
	}
	if ($doStats) {
		report_statistics();
	}
}

# -- Subroutines --

sub parse_blacklist() {
	open(BLACKLIST, "$dir/sj-blacklist.txt");
	my @list = <BLACKLIST>;
	close(BLACKLIST);
	for my $ga (@list) {
		chop $ga;
		if ($ga && $ga !~ /^#/) {
			$blacklist{$ga} = 1;
		}
	}
}

sub resolve_artifacts($) {
	my ($printList) = @_;

	my $cacheFile = "$dir/sj-hierarchy.cache";
	if (-e $cacheFile) {
		# build versions table from cache
		print STDERR "==> Reading artifact list from cache...\n";

		open(CACHE, "$cacheFile");
		my @gavs = <CACHE>;
		close(CACHE);
		for my $gav (@gavs) {
			chop $gav;
			my ($groupId, $artifactId, $version) = split(':', $gav);
			my $ga = "$groupId:$artifactId";
			if ($blacklist{$ga}) { next; }
			$versions{$ga} = $version;
			if ($printList) { print "$gav\n"; }
		}
	}
	else {
		# build versions table from remote repository
		print STDERR "==> Scanning for artifacts...\n";

		open(CACHE, ">$cacheFile");
		for my $groupId (@groupIds) {
			my @artifactIds = artifacts($groupId);
			for my $artifactId (@artifactIds) {
				my $ga = "$groupId:$artifactId";
				if ($blacklist{$ga}) { next; }

				# determine the latest version
				my $version = version($ga);
				if ($version) {
					if ($printList) { print "$ga:$version\n"; }
					print CACHE "$ga:$version\n";
				}
			}
		}
		close(CACHE);
	}
}

# Builds a parent-child tree of POMs
sub build_tree() {
	for my $ga (keys %versions) {
		my $version = version($ga);
		$version || next;
		my $parent = parent($ga);
		if (!$pomTree{$parent}) {
			my @children = ();
			$pomTree{$parent} = \@children;
		}
		my $children = $pomTree{$parent};
		push @{$children}, $ga;
	}
}

# Makes a list of SCMs associated with the artifacts.
sub list_scms() {
	my %scms;
	for my $ga (keys %versions) {
		my $version = version($ga);
		$version || next;
		my $scm = scm($ga);
		if (!$scm) {
			print STDERR "==> [WARNING] $ga:$version has no SCM\n";
			next;
		}
		if ($scm !~ /^scm:git:/) {
			print STDERR "==> [WARNING] $ga:$version SCM is not git\n";
			next;
		}
		$scm =~ s/^scm:git://;
		$scms{$scm} = 1;
	}
	for my $scm (sort keys %scms) {
		print "$scm\n";
	}
}

# Reports some statistics.
sub report_statistics() {
	my @gavs;
	for my $ga (keys %versions) {
		push @gavs, "$ga:$versions{$ga}";
	}
	for my $groupId (@groupIds) {
		my @total = grep(/^$groupId/, @gavs);
		my @poms = grep(/:pom-/, @total);
		my @snapshots = grep(/-SNAPSHOT$/, @total);
		my @pomSnapshots = grep(/:pom-/, @snapshots);

		my $totalCount = scalar @total;
		my $pomCount = scalar @poms;
		my $snapshotCount = scalar @snapshots;
		my $pomSnapshotCount = scalar @pomSnapshots;

		my $releaseCount = $totalCount - $snapshotCount;
		my $pomReleaseCount = $pomCount - $pomSnapshotCount;
		print "$groupId: $totalCount total ($releaseCount releases, " .
			"$snapshotCount snapshots); $pomCount poms " .
			"($pomReleaseCount releases, $pomSnapshotCount snapshots)\n";
	}
}

# Recursively prints out the POM tree
sub dump_tree($$) {
	my ($ga, $indent) = @_;
	for (my $i = 0; $i < $indent; $i++) { print ' '; }
	print "* $ga\n";
	my $children = $pomTree{$ga};
	if (!$children) { return; }
	for my $child (@{$children}) {
		dump_tree($child, $indent + 2);
	}
}

# Computes the latest version of a GA, caching the result.
sub version($) {
	my ($ga) = @_;
	if (!$versions{$ga}) {
		$versions{$ga} = execute("$dir/maven-helper.sh latest-version \"$ga\"");
	}
	return $versions{$ga};
}

# Obtains the path to the given GAV's POM in the local repository.
sub pom_path($) {
	my ($gav) = @_;
	my ($groupId, $artifactId, $version) = split(':', $gav);
	$groupId =~ s/\./\//g;
	my $pomPath = "$home/.m2/repository/$groupId/" .
		"$artifactId/$version/$artifactId-$version.pom";
	unless (-e $pomPath) {
		# download POM to local repository cache
		print STDERR "==> Resolving $gav from remote repository\n";
		execute("mvn dependency:get -Dartifact=$gav:pom " .
			"-DremoteRepositories=imagej.public::default::" .
			"http://maven.imagej.net/content/groups/public " .
			"-Dtransitive=false");
	}
	return $pomPath;
}

# Obtains the POM XML for the given GA, caching the result.
sub pom_xml($) {
	my ($ga) = @_;
	if (!$pomXML{$ga}) {
		my $version = version($ga);
		$pomXML{$ga} = XMLin(pom_path("$ga:$version"));
	}
	return $pomXML{$ga};
}

# Computes the parent of a GA.
sub parent($) {
	my ($ga) = @_;
	my $xml = pom_xml($ga);
	my $groupId = $xml->{parent}->{groupId};
	my $artifactId = $xml->{parent}->{artifactId};
	return "$groupId:$artifactId";
}

# Computes the SCM of a GA.
sub scm($) {
	my ($ga) = @_;
	my $xml = pom_xml($ga);
	my $scm = $xml->{scm}->{connection};
	if (!$scm) {
		my $parent = parent($ga);
		return $parent && $parent ne ':' ? scm($parent) : undef;
	}
	return $scm;
}

# Obtains a list of artifacts in the given group.
sub artifacts($) {
	my ($groupId) = @_;
	return split("\n", execute("$dir/maven-helper.sh artifacts \"$groupId\""));
}

# Executes the given shell command.
sub execute($) {
	my ($command) = @_;
	my $result = `$command`;
	chop $result;
	return $result;
}
