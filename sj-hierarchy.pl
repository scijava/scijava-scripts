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

my $quiet;
my $verbose;

# -- Main --

{
	my $doCI;
	my $doHelp;
	my $doList;
	my $doParents;
	my $doSCM;
	my $doStats;
	my $doTree;

	for my $cmd (@ARGV) {
		if ($cmd =~ /^-\w+$/) {
			for my $c (split(//, $cmd)) {
				if ($c eq 'c') { $doCI = 1; }
				elsif ($c eq 'g') { $doSCM = 1; }
				elsif ($c eq 'l') { $doList = 1; }
				elsif ($c eq 'p') { $doParents = 1; }
				elsif ($c eq 's') { $doStats = 1; }
				elsif ($c eq 't') { $doTree = 1; }
				elsif ($c eq 'q') { $quiet = 1; }
				elsif ($c eq 'v') { $verbose = 1; }
			}
		}
		elsif ($cmd eq '--ci') { $doCI = 1; }
		elsif ($cmd eq '--help') { $doHelp = 1; }
		elsif ($cmd eq '--list') { $doList = 1; }
		elsif ($cmd eq '--parents') { $doParents = 1; }
		elsif ($cmd eq '--scm') { $doSCM = 1; }
		elsif ($cmd eq '--stats') { $doStats = 1; }
		elsif ($cmd eq '--tree') { $doTree = 1; }
		elsif ($cmd eq '--quiet') { $quiet = 1; }
		elsif ($cmd eq '--verbose') { $verbose = 1; }
		else { warning("Invalid argument: $cmd"); }
	}

	$doCI || $doList || $doParents || $doSCM || $doStats || $doTree ||
		($doHelp = 1);

	if ($doHelp) {
		print STDERR "Usage: sj-hierachy.pl [-glstqv]\n";
		print STDERR "\n";
		print STDERR "  -c, --ci      : list involved CI URLs\n";
		print STDERR "  -g, --scm     : list involved SCM URLs\n";
		print STDERR "  -l, --list    : list SciJava artifacts\n";
		print STDERR "  -p, --parents : show table of artifact parents\n";
		print STDERR "  -s, --stats   : show some statistics about the artifacts\n";
		print STDERR "  -t, --tree    : display artifacts in a tree structure\n";
		print STDERR "  -q, --quiet   : emit fewer details to stderr\n";
		print STDERR "  -v, --verbose : emit more details to stderr\n";
		exit 1;
	}

	parse_blacklist();
	resolve_artifacts();

	if ($doCI) {
		list_cis();
	}
	if ($doList) {
		show_list();
	}
	if ($doParents) {
		show_parents();
	}
	if ($doTree) {
		show_tree();
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
		info("Reading artifact list from cache...");

		open(CACHE, "$cacheFile");
		my @gavs = <CACHE>;
		close(CACHE);
		for my $gav (@gavs) {
			chop $gav;
			my ($groupId, $artifactId, $version) = split(':', $gav);
			my $ga = "$groupId:$artifactId";
			if ($blacklist{$ga}) {
				detail("Ignoring blacklisted artifact: $ga");
				next;
			}
			$versions{$ga} = $version;
			detail($gav);
		}
	}
	else {
		# build versions table from remote repository
		info("Scanning for artifacts...");

		open(CACHE, ">$cacheFile");
		for my $groupId (@groupIds) {
			my @artifactIds = artifacts($groupId);
			for my $artifactId (@artifactIds) {
				my $ga = "$groupId:$artifactId";
				if ($blacklist{$ga}) {
					detail("Ignoring blacklisted artifact: $ga");
					next;
				}

				# determine the latest version
				my $version = version($ga);
				if ($version =~ /-SNAPSHOT$/) {
					detail("Ignoring SNAPSHOT-only artifact: $ga");
				}
				elsif ($version) {
					info("$ga:$version");
					print CACHE "$ga:$version\n";
				}
			}
		}
		close(CACHE);
	}
}

# Displays a list of artifacts
sub show_list() {
	for my $ga (sort keys %versions) {
		output("$ga:$versions{$ga}");
	}
}

# Displays a list of artifacts
sub show_parents() {
	my $width = 0;
	for my $ga (keys %versions) {
		my $gav = "$ga:" . version($ga);
		my $w = length($gav);
		if ($w > $width) { $width = $w; }
	}
	$width++;

	for my $ga (sort keys %versions) {
		my $gav = "$ga:" . version($ga);
		my $parent = parent($ga);
		my $pGAV = $parent eq ':' ? '(none)' : "$parent:" . version($parent);
		printf("%${width}s : %s\n", $gav, $pGAV);
	}
}

# Displays a parent-child tree of POMs
sub show_tree() {
	# build the tree
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

	# display the tree
	dump_tree("org.scijava:pom-scijava", 0);
}

# Makes a list of CIs associated with the artifacts.
sub list_cis() {
	for my $ga (keys %versions) {
		my $version = version($ga);
		$version || next;
		my $ci = ci($ga);
		if (!$ci) {
			warning("No CI for artifact: $ga:$version");
			next;
		}
		output("$ga: $ci");
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
			warning("No SCM for artifact: $ga:$version");
			next;
		}
		if ($scm !~ /^scm:git:/) {
			warning("Unsupported SCM for artifact: $ga:$version");
			next;
		}
		$scm =~ s/^scm:git://;
		$scms{$scm} = 1;
	}
	for my $scm (sort keys %scms) {
		output($scm);
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
		output("$groupId: $totalCount total ($releaseCount releases, " .
			"$snapshotCount snapshots); $pomCount poms " .
			"($pomReleaseCount releases, $pomSnapshotCount snapshots)");
	}
}

# Recursively prints out the POM tree
sub dump_tree($$) {
	my ($ga, $indent) = @_;
	output(lead($indent) . "* $ga");
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
		info("Resolving $gav from remote repository");
		execute("mvn org.apache.maven.plugins:maven-dependency-plugin:2.8:get " .
			"-Dartifact=$gav:pom -DremoteRepositories=imagej.public::default::" .
			"http://maven.imagej.net/content/groups/public -Dtransitive=false");
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

# Computes the CI of a GA.
sub ci($) {
	my ($ga) = @_;
	my $xml = pom_xml($ga);
	my $ci = $xml->{ciManagement}->{url};
	if (!$ci) {
		my $parent = parent($ga);
		return $parent && $parent ne ':' ? ci($parent) : undef;
	}
	return $ci;
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

	my $url = $groupId;
	$url =~ s/\./\//g;
	$url = "http://maven.imagej.net/content/groups/public/$url/";

	my @links = `curl -fs "$url"`;
	my @artifacts = ();
	for my $link (@links) {
		if ($link =~ /<a href=\"$url.*\/<\/a>/) {
			chop $link;
			$link =~ s/ *<[^>]*>(.*)\/<\/a>/$1/;
			push @artifacts, $link;
		}
	}

	return @artifacts;
}

# Executes the given shell command.
sub execute($) {
	my ($command) = @_;
	detail($command);
	my $result = `$command`;
	chop $result;
	return $result;
}

sub lead($) {
	my ($indent) = @_;
	my $lead = '';
	for (my $i = 0; $i < $indent; $i++) { $lead .= ' '; }
	return $lead;
}

sub output($) {
	my ($message) = @_;
	print "$message\n";
}

sub info($) {
	my ($message) = @_;
	unless ($quiet) {
		print STDERR "==> $message\n";
	}
}

sub detail($) {
	my ($message) = @_;
	if ($verbose) {
		print STDERR "==> $message\n";
	}
}

sub warning($) {
	my ($message) = @_;
	print STDERR "[WARNING] $message\n";
}

sub error($) {
	my ($message) = @_;
	print STDERR "[ERROR] $message\n";
}
