#!/usr/bin/perl

# check-release.pl - checks whether the tip of the master branch
#                    has changed since the last release.

use strict;
use File::Basename qw(dirname);
use Getopt::Long;

my $ask_nexus_for_latest_version;
my $git_fetch_first;

GetOptions ('ask-nexus-for-latest-version' => \$ask_nexus_for_latest_version,
  'git-fetch-first' => \$git_fetch_first)
or die ('Usage: ' . $0
  . ' [--ask-nexus-for-latest-version] [--git-fetch-first]');

# add SciJava scripts to the search path
$ENV{PATH} .= ':' . dirname($0);

if ($git_fetch_first) {
  # make sure the latest tags are available
  `git fetch --tags 2> /dev/null`;
}

if (! -e "pom.xml") {
  print STDERR "[ERROR] No pom.xml: " . `pwd`;
  exit 1;
}

# determine the project's GAV
my $gav = `sh maven-helper.sh gav-from-pom pom.xml`;
chomp $gav;
my ($groupId, $artifactId, $version) = split(':', $gav);
my $ga = "$groupId:$artifactId";

my ($latest, $tag);
if ($ask_nexus_for_latest_version) {
  # determine the latest release
  $latest = `sh maven-helper.sh latest-version \"$ga\"`;
  chomp $latest;

  if (!$latest || $latest =~ /\-SNAPSHOT$/) {
    print STDERR "[ERROR] $ga: No release version\n";
    exit 2;
  }

  # compare the release tag with the master branch
  $tag = "$artifactId-$latest";
  if ($tag =~ /^pom-(.*)$/) {
    $tag = $1;
  }

  if (!`git tag -l | grep $tag`) {
    print STDERR "[ERROR] $ga: No release tag: $tag\n";
    exit 3;
  }
} else {
  my $name = $artifactId;
  $name =~ s/^pom-//;
  my $prefix = "refs/tags/$name-";

  # just use the available tags to determine the latest release
  $tag = `git for-each-ref --count=1 --sort='-*authordate' --format='%(refname)' $prefix\*`;
  chomp $tag;
  $tag =~ s/refs\/tags\///;
  $latest = substr($tag, length($name) + 1);
}

my @commits = `git cherry -v $tag origin/master`;
my $commitCount = @commits;
if ($commitCount > 1 ||
  $commitCount == 1 && $commits[0] !~ /Bump to next development cycle$/)
{
  # new commits on master; a release is potentially needed
  print "$ga: $commitCount commits on master since $latest\n";
}
