#!/usr/bin/perl

# prettify-status.pl - converts plaintext status to HTML.
#
# Usage: prettify-status.pl < status.txt > status.html

use strict;

my %orgs = (
  'org.scijava' => 'scijava',
  'io.scif'     => 'scifio',
  'net.imagej'  => 'imagej',
  'net.imglib2' => 'imglib',
);

sub rowClass($$) {
  my $index = shift;
  my $count = shift;
  my $rowClass = $index % 2 == 0 ? 'even' : 'odd';
  if ($index == 0) { $rowClass .= ' first'; }
  if ($index == $count - 1) { $rowClass .= ' last'; }
  return $rowClass;
}

# parse status output
my @ahead = ();
my @released = ();
my @warnings = ();

my @lines = <>;
sort(@lines);

for my $line (@lines) {
  chomp $line;
  if ($line =~ /([^:]+):([^:]+): (\d+) commits on (\w+) since (.+)/) {
    my $groupId = $1;
    my $artifactId = $2;
    my $commitCount = $3;
    my $branch = $4;
    my $version = $5;
    my $tag = "$artifactId-$version";
    my $org = $orgs{$groupId};
    if (not $org) {
      push @warnings, "No known GitHub org for groupId '$groupId'\n";
    }
    my $link = "https://github.com/$orgs{$groupId}/$artifactId";
    if ($commitCount > 0) {
      # a release is needed
      push @ahead, "<td class=\"first\"></td>\n" .
        "<td><a href=\"$link\">$groupId:$artifactId</a></td>\n" .
        "<td><a href=\"$link/compare/$tag...$branch\">$commitCount</a></td>\n" .
        "<td><a href=\"$link/tree/$branch\">$branch</a></td>\n" .
        "<td><a href=\"$link/tree/$tag\">$version</a></td>\n";
    }
    else {
      # everything is up to date
      push @released, "<td class=\"first\"></td>\n" .
        "<td><a href=\"$link\">$groupId:$artifactId</a></td>\n" .
        "<td><a href=\"$link/tree/$tag\">$version</a></td>\n";
    }
  }
  else {
    push @warnings, $line;
  }
}

# dump prettified version

print "<html>\n";
print "<head>\n";
print "<title>SciJava software status</title>\n";
print "<link type=\"text/css\" rel=\"stylesheet\" href=\"status.css\" />\n";
print "<link rel=\"icon\" type=\"image/png\" href=\"favicon.png\" />\n";
print "</head>\n";
print "<body>\n\n";

if (@warnings > 0) {
  print "<div class=\"warnings\">\n";
  print "<h2>Warnings</h2>\n";
  print "<ul class=\"warnings\">\n";
  my $rowIndex = 0;
  my $rowCount = @warnings;
  for my $line (@warnings) {
    my $rowClass = rowClass($rowIndex++, $rowCount);
    print "<li class=\"$rowClass\">\n$line\n</li>\n";
  }
  print "</ul>\n";
  print "</div>\n\n";
}

if (@ahead > 0) {
  print "<div class=\"ahead\">\n";
  print "<h2>Ahead</h2>\n";
  print "<table>\n";
  print "<tr>\n";
  print "<th>&nbsp;</th>\n";
  print "<th>Project</th>\n";
  print "<th>Commits</th>\n";
  print "<th>Branch</th>\n";
  print "<th>Latest version</th>\n";
  print "</tr>\n";
  my $rowIndex = 0;
  my $rowCount = @ahead;
  for my $row (@ahead) {
    my $rowClass = rowClass($rowIndex++, $rowCount);
    print "<tr class=\"$rowClass\">\n$row</tr>\n";
  }
  print "</table>\n";
  print "</div>\n\n";
}

if (@released > 0) {
  print "<div class=\"released\">\n";
  print "<h2>Released</h2>\n";
  print "<table>\n";
  print "<tr>\n";
  print "<th>&nbsp;</th>\n";
  print "<th>Project</th>\n";
  print "<th>Latest version</th>\n";
  print "</tr>\n";
  my $rowIndex = 0;
  my $rowCount = @released;
  for my $row (@released) {
    my $rowClass = rowClass($rowIndex++, $rowCount);
    print "<tr class=\"$rowClass\">\n$row</tr>\n";
  }
  print "</table>\n";
  print "</div>\n\n";
}

print "<div class=\"footer\">&nbsp;</div>\n\n";

print "</body>\n";
print "</html>\n";
