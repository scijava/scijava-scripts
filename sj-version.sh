#!/bin/sh

# Script to print version properties for a given pom-scijava release.

# Examples:
# sj-version.sh 1.70
# sj-version.sh 1.70 1.74

version="$1"
diff="$2"

repo="https://maven.scijava.org/content/groups/public"

props() {
	if [ -e "$1" ]
	then
		# extract version properties from the given file path
		pomContent=$(cat "$1")
	else
		# assume argument is a version number of pom-scijava
		pomURL="$repo/org/scijava/pom-scijava/$1/pom-scijava-$1.pom"
		pomContent=$(curl -s "$pomURL")
	fi

	# grep the pom-scijava-base parent version of out of the POM,
	# then rip out the version properties from that one as well!
	psbVersion=$(echo "$pomContent" |
		grep -A1 '<artifactId>pom-scijava-base' |
		grep '<version>' | sed 's;.*>\([^<]*\)<.*;\1;')
	psbContent=
	if [ "$psbVersion" ]
	then
		psbURL="$repo/org/scijava/pom-scijava-base/$psbVersion/pom-scijava-base-$psbVersion.pom"
		psbContent=$(curl -s "$psbURL")
	fi

	{ echo "$pomContent"; echo "$psbContent"; } |
		grep '\.version>' |
		sed -E -e 's/^				(.*)/\1 [DEV]/' |
		sed -E -e 's/^	*<(.*)\.version>(.*)<\/.*\.version>/\1 = \2/' |
		sort
}

if [ -z "$version" ]
then
	# try to extract version from pom.xml in this directory
	if [ -e pom.xml ]
	then
		version=$(grep -A 1 pom-scijava pom.xml | \
			grep '<version>' | \
			sed 's/<\/.*//' | \
			sed 's/.*>//')
	fi
fi

if [ -z "$version" ]
then
	echo "Usage: sj-version.sh version [version-to-diff]"
	exit 1
fi

if [ -n "$diff" ]
then
	# compare two versions
	props $version > $version.tmp
	props $diff > $diff.tmp
	diff -y $version.tmp $diff.tmp
	rm $version.tmp $diff.tmp
else
	# dump props for one version
	props $version
fi
