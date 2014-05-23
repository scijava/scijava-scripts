#!/usr/bin/perl

# check-release.pl - checks whether the tip of the master branch
#                    has changed since the last release.

use strict;
use File::Basename qw(dirname);

# add SciJava scripts to the search path
$ENV{PATH} .= ':' . dirname($0);

# make sure the latest commits and tags are available
`git fetch origin master 2> /dev/null`;
`git fetch --tags 2> /dev/null`;

if (! -e "pom.xml") {
  print STDERR "[ERROR] No pom.xml: " . `pwd`;
  exit 1;
}

# determine the project's GAV
my $gav = `maven-helper.sh gav-from-pom pom.xml`;
chomp $gav;
my ($groupId, $artifactId, $version) = split(':', $gav);
my $ga = "$groupId:$artifactId";

# determine the latest release
my $latest = `maven-helper.sh latest-version \"$ga\"`;
chomp $latest;

if (!$latest || $latest =~ /\-SNAPSHOT$/) {
  print STDERR "[ERROR] $ga: No release version\n";
  exit 2;
}

# compare the release tag with the master branch
my $tag = "$artifactId-$latest";
if ($tag =~ /^pom-(.*)$/) {
  $tag = $1;
}

if (!`git tag -l | grep $tag`) {
  print STDERR "[ERROR] $ga: No release tag: $tag\n";
  exit 3;
}

my @commits = `git cherry -v $tag origin/master`;
my $commitCount = @commits;
if ($commitCount > 1 ||
  $commitCount == 1 && $commits[0] !~ /Bump to next development cycle$/)
{
  # new commits on master; a release is potentially needed
  print "$ga: $commitCount commits on master since $latest\n";
}
