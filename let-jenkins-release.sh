#!/bin/sh

die () {
	echo "$*" >&2
	exit 1
}

simulate=
while test $# -gt 0
do
	case "$1" in
	--simulate)
		simulate=t
		;;
	*)
		die "Unhandled option: $1"
		;;
	esac
	shift
done

url="$(git config remote.origin.url)" ||
die "Could not obtain the current URL"

case "$url" in
http://github.com/*|https://github.com/*|git://github.com/*|ssh://github.com/*|ssh://git@github.com/*)
	repo=${url#*://*github.com/}
	;;
git@github.com:*|github.com:*|github:*)
	repo=${url#*:}
	;;
*)
	die "Not a GitHub URL: $url"
	;;
esac
repo=${repo%/}
repo=${repo%.git}
repository_url=$repo

test refs/heads/master = "$(git rev-parse --symbolic-full-name HEAD)" ||
die "Not on master branch!"

git update-index -q --refresh &&
git diff-files --quiet --ignore-submodules &&
git diff-index --cached --quiet --ignore-submodules HEAD -- ||
die "There are uncommitted changes!"

git fetch --tags ||
die "Could not fetch"

commit="$(git rev-parse HEAD)" &&
upstream="$(git rev-parse origin/master)" ||
die "Could not obtain current revision"

test $commit = $upstream ||
die "Not up-to-date: $(printf '\n%s' "$(git log --graph --oneline \
	--left-right --boundary ...$upstream)")"

pom="$(cat pom.xml)" &&
snapshot="$(echo "$pom" |
	sed -n 's|^	<version>\(.*\)</version>|\1|p')" ||
die "Could not obtain version"

version=${snapshot%-SNAPSHOT}
test "$version" != "$snapshot" ||
die "Not a -SNAPSHOT version: $snapshot"

test ! -t 0 || {
	printf 'Version? [%s]: ' "$version"
	read line
	test -z "$line" || version="$line"
}

jenkins_url=http://jenkins.imagej.net/job/Release-Version/buildWithParameters
params="REPOSITORY_URL=$repository_url&COMMIT=$commit&VERSION_STRING=$version"
if test -z "$simulate"
then
	curl --netrc -X POST "$jenkins_url?$params"
else
	echo curl --netrc -X POST "$jenkins_url?$params"
fi
