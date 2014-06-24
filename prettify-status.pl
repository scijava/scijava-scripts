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
my @table = ();
my @warnings = ();
while (<>) {
  my $line = $_;
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
    push @table, "<td><a href=\"$link\">$groupId:$artifactId</a></td>\n" .
      "<td><a href=\"$link/compare/$tag...$branch\">$commitCount</a></td>\n" .
      "<td><a href=\"$link/tree/$branch\">$branch</a></td>\n" .
      "<td><a href=\"$link/tree/$tag\">$version</a></td>\n";
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
print "</head>\n";
print "<body>\n\n";

print "<h2>Warnings</h2>\n";
print "<ul>\n";
my $rowIndex = 0;
my $rowCount = @warnings;
for my $line (@warnings) {
  my $rowClass = rowClass($rowIndex++, $rowCount);
  print "<li class=\"$rowClass\">\n$line</li>\n";
}
print "</ul>\n\n";

print "<h2>Status</h2>\n";
print "<table>\n";
print "<tr>\n";
print "<th>Project</th>\n";
print "<th>Commits</th>\n";
print "<th>Branch</th>\n";
print "<th>Latest version</th>\n";
print "</tr>\n";
my $rowIndex = 0;
my $rowCount = @table;
for my $row (@table) {
  my $rowClass = rowClass($rowIndex++, $rowCount);
  print "<tr class=\"$rowClass\">\n$row</tr>\n";
}
print "</table>\n\n";

print "</body>\n";
print "</html>\n";
