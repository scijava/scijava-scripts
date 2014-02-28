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
);

my $home = $ENV{"HOME"};
my $dir = `dirname "$0"`;
chop $dir;

my %blacklist;
my %versions;
my %pomXML;
my %parents;
my %pomTree;

# -- Main --

{
	parse_blacklist();
	resolve_artifacts();
	build_tree();
	dump_tree("org.scijava:pom-scijava", 0);
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

sub resolve_artifacts() {
	my $cacheFile = "$dir/sj-hierarchy.cache";
	if (-e $cacheFile) {
		# build versions table from cache
		open(CACHE, "$cacheFile");
		my @gavs = <CACHE>;
		close(CACHE);
		for my $gav (@gavs) {
			chop $gav;
			my ($groupId, $artifactId, $version) = split(':', $gav);
			my $ga = "$groupId:$artifactId";
			if ($blacklist{$ga}) { next; }
			$versions{$ga} = $version;
			print "$gav\n";
		}
	}
	else {
		# build versions table from remote repository
		open(CACHE, ">$cacheFile");
		print STDERR "==> Scanning for artifacts...\n";
		for my $groupId (@groupIds) {
			my @artifactIds = artifacts($groupId);
			for my $artifactId (@artifactIds) {
				my $ga = "$groupId:$artifactId";
				if ($blacklist{$ga}) { next; }

				# determine the latest version
				my $version = version($ga);
				if ($version) {
					print "$ga:$version\n";
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
		if (not defined $pomTree{$parent}) {
			my @children = ();
			$pomTree{$parent} = \@children;
		}
		my $children = $pomTree{$parent};
		push @{$children}, $ga;
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
	if (not defined $versions{$ga}) {
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
	if (not defined $pomXML{$ga}) {
		my $version = version($ga);
		$pomXML{$ga} = XMLin(pom_path("$ga:$version"));
	}
	return $pomXML{$ga};
}

# Computes the parent of a GA, caching the result.
sub parent($) {
	my ($ga) = @_;
	if (not defined $parents{$ga}) {
		my $xml = pom_xml($ga);
		my $groupId = $xml->{parent}->{groupId};
		my $artifactId = $xml->{parent}->{artifactId};
		$parents{$ga} = "$groupId:$artifactId";
	}
	return $parents{$ga};
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
