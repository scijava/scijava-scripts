#!/usr/bin/perl

# check-release.pl - checks whether the tip of the master branch
#                    has changed since the specified release.

use strict;
use File::Basename qw(dirname);
use Getopt::Long;

# -- Constants --

my $cachePath = "$ENV{HOME}/.m2/repository";

# -- Options --

my $release_version;
my $verbose;
my $debug;

GetOptions(
  'release-version=s' => \$release_version,
  'verbose' => \$verbose,
  'debug' => \$debug)
or die ('Usage: ' . $0 .
  ' [--release-version <version>]' .
  ' [--verbose]' .
  ' [--debug]');

# -- Subroutines --

sub debug($) {
  my $msg = shift;
  if ($debug) { print STDERR "[DEBUG] $msg\n"; }
}

sub error($$) {
  my $no = shift;
  my $msg = shift;
  print STDERR "[ERROR] $msg\n";
  exit $no;
}

sub tagExists($) {
  my $tag = shift;
  return `git tag -l | grep '^$tag\$'` ? 1 : 0;
}

sub latestRelease($) {
  my $ga = shift;

  debug("Downloading latest release metadata");

  # download the latest release POM from the Maven repository
  `mvn dependency:get -Dartifact=$ga:LATEST -Dpackaging=pom`;

  # extract the latest release version from local repository cache metadata
  my $gaPath = $ga;
  $gaPath =~ s/[\.:]/\//g;
  my $release = `grep release "$cachePath/$gaPath"/*.xml | head -n 1`;
  chomp $release;
  $release =~ s/.*<release>//;
  $release =~ s/<\/release>.*//;
  return $release;
}

sub releaseRef($$$) {
  my $groupId = shift;
  my $artifactId = shift;
  my $releaseVersion = shift;

  # look for a suitable tag
  my $tag = "$artifactId-$releaseVersion";
  if (tagExists($tag)) { return $tag; }
  if ($tag =~ /_$/) {
    $tag =~ s/_$//;
    if (tagExists($tag)) { return $tag; }
  }
  if ($tag =~ /^pom-/) {
    $tag =~ s/^pom-//;
    if (tagExists($tag)) { return $tag; }
  }
  $tag = "v$releaseVersion";
  if (tagExists($tag)) { return $tag; }

  # no tag found; extract ref from the JAR
  return extractRef($groupId, $artifactId, $releaseVersion);
}

sub extractRef($$$) {
  my $groupId = shift;
  my $artifactId = shift;
  my $version = shift;

  my $ga = "$groupId:$artifactId";
  my $gaPath = $ga;
  $gaPath =~ s/[\.:]/\//g;
  my $jarPath = "$cachePath/$gaPath/$version/$artifactId-$version.jar";

  if (! -e $jarPath) {
    # download the version from the Maven repository
    debug("Fetching JAR: '$jarPath'");
    `mvn dependency:get -Dartifact=$ga:$version`;
  }

  if (! -e $jarPath) {
    # the requested GAV could not be found
    return '';
  }

  # extract Implementation-Build from the JAR manifest
  debug("Extracting release ref from JAR");
  my $implBuild = `unzip -q -c "$jarPath" META-INF/MANIFEST.MF | grep Implementation-Build`;
  chomp $implBuild;
  $implBuild =~ s/.* ([0-9a-f]+).*/\1/;
  return $implBuild;
}

# -- Main --

# add SciJava scripts to the search path
$ENV{PATH} .= ':' . dirname($0);

if (! -e "pom.xml") {
  error(1, "No pom.xml: " . `pwd`);
}

# determine the project's GAV
my $gav = `maven-helper.sh gav-from-pom pom.xml`;
chomp $gav;
my ($groupId, $artifactId, $version) = split(':', $gav);
my $ga = "$groupId:$artifactId";

debug("groupId = $groupId");
debug("artifactId = $artifactId");

# make sure the latest tags are available
`git fetch --tags 2> /dev/null`;

if (!$release_version) {
  # no release version specified; use the latest release
  $release_version = latestRelease($ga);
}

debug("Release version = $release_version");

if (!$release_version || $release_version =~ /\-SNAPSHOT$/) {
  error(2, "$ga: No release version");
}

my $releaseRef = releaseRef($groupId, $artifactId, $release_version);

if (!$releaseRef) {
  error(3, "$ga: No ref for version $release_version");
}

debug("Release ref = $releaseRef");

my $sourceDirs = `git ls-files */src/main/ src/main/ | sed 's-/main/.*-/main-' | uniq | tr '\n' ' '`;

if (!$sourceDirs) {
  error(4, "[ERROR] $ga: No sources to compare");
}

debug("Source directories = $sourceDirs");

my @commits = `git rev-list $releaseRef...origin/master -- $sourceDirs`;
my $commitCount = @commits;

# ignore commits which are known to be irrelevant
foreach my $commit (@commits) {
  chomp $commit;
  my $commitMessage = `git log -1 --oneline $commit`;
  chomp $commitMessage;
  if ($commitMessage =~ /^[a-z0-9]{7} [Hh]appy .*[Nn]ew [Yy]ear/) {
    # Ignore "Happy New Year" copyright header updates
    debug("Ignoring Happy New Year commit: $commit");
    $commitCount--;
  }
  elsif ($commitMessage =~ /^[a-z0-9]{7} [Uu]pdate.*[Cc]opyright.*20[0-9]{2}/) {
    # Ignore "Update copyrights" copyright header updates
    debug("Ignoring copyright year update commit: $commit");
    $commitCount--;
  }
  elsif ($commitMessage =~ /^[a-z0-9]{7} [Uu]pdate license (blurb|header)s$/) {
    # Ignore "Update license headers" updates
    debug("Ignoring 'Update license headers' commit: $commit");
    $commitCount--;
  }
  elsif ($commitMessage =~ /^[a-z0-9]{7} Organize imports$/) {
    # Ignore "Organize imports" updates
    debug("Ignoring 'Organize imports' commit: $commit");
    $commitCount--;
  }
}

if ($verbose || $commitCount > 0) {
  # new commits on master; a release is potentially needed
  my @allCommits = `git rev-list $releaseRef...origin/master`;
  my $totalCommits = @allCommits;
  print "$ga: $commitCount/$totalCommits commits on master since $release_version\n";
}
