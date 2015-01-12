#!/bin/sh

# This script tests whether a given version bump is valid.

die() {
	echo "$*" >&2
	exit 1
}

succeed() {
	echo "$*" >&2
	exit 0
}

major() {
	major=${1%%.*}
	test -n "$major" || die "Invalid SemVer: $1"
	echo $major
}

minor() {
	tmp=${1#*.}
	minor=${tmp%%.*}
	test -n "$minor" || die "Invalid SemVer: $1"
	echo $minor
}

patch() {
	patch=${1##*.}
	test -n "$patch" || die "Invalid SemVer: $1"
	echo $patch
}

SNAPSHOT="${1%-SNAPSHOT}"
RELEASE="$2"

test -n "$RELEASE" -a -n "$SNAPSHOT" ||
	die "Usage: valid-semver-bump.sh previous-snapshot-version new-release-version"

test "$RELEASE" = "$SNAPSHOT" &&
	succeed "Detected DEFAULT version bump"

NEW_MAJOR=$(major $RELEASE)
NEW_MINOR=$(minor $RELEASE)
NEW_PATCH=$(patch $RELEASE)
OLD_MAJOR=$(major $SNAPSHOT)
OLD_MINOR=$(minor $SNAPSHOT)
OLD_PATCH=$(patch $SNAPSHOT)

# check for MINOR version bump
# e.g. 1.0.1-SNAPSHOT -> 1.1.0
if [ "$OLD_PATCH" -gt 0 ]
then
	test "$NEW_MAJOR" -eq "$OLD_MAJOR" \
		-a "$NEW_MINOR" -eq "$((OLD_MINOR+1))" \
		-a "$NEW_PATCH" -eq 0 &&
		succeed "Detected MINOR version bump"
fi

# check for MAJOR version bump
# e.g. 1.1.0-SNAPSHOT -> 2.0.0
# e.g. 1.0.1-SNAPSHOT -> 2.0.0
if [ "$OLD_PATCH" -gt 0 -o "$OLD_MINOR" -gt 0 ]
then
	test "$NEW_MAJOR" -eq "$((OLD_MAJOR+1))" \
		-a "$NEW_MINOR" -eq 0 \
		-a "$NEW_PATCH" -eq 0 &&
		succeed "Detected MAJOR version bump"
fi

die "Invalid version bump: $SNAPSHOT -> $RELEASE"
