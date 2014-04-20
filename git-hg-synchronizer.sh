#!/bin/sh

# This script uses Git for Windows' remote-hg to mirror Mercurial repositories.
# It is meant to be run as a Jenkins job.

set -e

type git-remote-hg > /dev/null 2>&1 || {
	mkdir -p "$HOME"/bin &&
	if test ! -x "$HOME"/bin/git-remote-hg
	then
		curl -Lfs https://github.com/msysgit/git/raw/master/contrib/remote-helpers/git-remote-hg > "$HOME"/bin/git-remote-hg &&
		chmod a+x "$HOME"/bin/git-remote-hg
	fi &&
	export PATH="$HOME"/bin:$PATH
} || {
	echo "Could not install git-remote-hg" >&2
	exit 1
}

HG_URL="$1"
shift

test -d .git || git init --bare
test a"hg::$HG_URL" = a"$(git config remote.origin.url)" ||
git remote add --mirror=fetch origin hg::"$HG_URL"

git fetch origin

git gc --auto
for url
do
	git push --all "$url"
	git push --tags "$url"
done
