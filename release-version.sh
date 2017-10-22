#!/bin/sh

die () {
	echo "$*" >&2
	exit 1
}

MAVEN_HELPER="$(cd "$(dirname "$0")" && pwd)/maven-helper.sh"

maven_helper () {
	sh -$- "$MAVEN_HELPER" "$@" ||
	die "Could not find maven-helper in '$MAVEN_HELPER'"
}

VALID_SEMVER_BUMP="$(cd "$(dirname "$0")" && pwd)/valid-semver-bump.sh"

valid_semver_bump () {
	test -f "$VALID_SEMVER_BUMP" ||
		die "Could not find valid-semver-bump in '$VALID_SEMVER_BUMP'"
	sh -$- "$VALID_SEMVER_BUMP" "$@" || die
}

verify_gpg_settings () {
	test -f .travis/signingkey.asc.enc ||
		die 'GPG configuration not found. Please use travisify.sh to add it.
See also: https://github.com/scijava/pom-scijava/wiki/GPG-Signing'
}

verify_git_settings () {
	if [ ! "$SKIP_PUSH" ]
	then
		push=$(git remote -v | grep origin | grep '(push)')
		test "$push" || die 'No push URL found for remote origin'
		echo "$push" | grep -q 'git:/' && die 'Remote origin is read-only'
	fi
}

verify_netrc_settings () {
	grep -q 'machine maven.imagej.net' "$HOME/.netrc" 2>/dev/null &&
		grep -q 'login jenkins-expire-cache' "$HOME/.netrc" 2>/dev/null ||
		die 'maven.imagej.net cache expiration credentials not found in .netrc. Please add it:
machine maven.imagej.net
login jenkins-expire-cache
password (the-correct-password)

See also: https://github.com/scijava/pom-scijava/wiki/Adding-Maven-Users'
}

IMAGEJ_BASE_REPOSITORY=-DaltDeploymentRepository=imagej.releases::default::dav:https://maven.imagej.net/content/repositories
IMAGEJ_RELEASES_REPOSITORY=$IMAGEJ_BASE_REPOSITORY/releases
IMAGEJ_THIRDPARTY_REPOSITORY=$IMAGEJ_BASE_REPOSITORY/thirdparty

BATCH_MODE=--batch-mode
SKIP_PUSH=
TAG=
DEV_VERSION=
EXTRA_ARGS=
ALT_REPOSITORY=
PROFILE=-Pdeploy-to-imagej
INVALIDATE_NEXUS=
DRY_RUN=
while test $# -gt 0
do
	case "$1" in
	--dry-run) DRY_RUN=echo;;
	--no-batch-mode) BATCH_MODE=;;
	--skip-push) SKIP_PUSH=t;;
	--tag=*)
		! git rev-parse --quiet --verify refs/tags/"${1#--*=}" ||
		die "Tag ${1#--*=} exists already!"
		TAG="-Dtag=${1#--*=}";;
	--dev-version=*|--development-version=*)
		DEV_VERSION="-DdevelopmentVersion=${1#--*=}";;
	--extra-arg=*|--extra-args=*)
		EXTRA_ARGS="$EXTRA_ARGS ${1#--*=}";;
	--alt-repository=imagej-releases)
		ALT_REPOSITORY=$IMAGEJ_RELEASES_REPOSITORY;;
	--alt-repository=imagej-thirdparty)
		ALT_REPOSITORY=$IMAGEJ_THIRDPARTY_REPOSITORY;;
	--alt-repository=*|--alt-deployment-repository=*)
		ALT_REPOSITORY="${1#--*=}";;
	--thirdparty=imagej)
		BATCH_MODE=
		SKIP_PUSH=t
		ALT_REPOSITORY=$IMAGEJ_THIRDPARTY_REPOSITORY;;
	--skip-gpg)
		EXTRA_ARGS="$EXTRA_ARGS -Dgpg.skip=true";;
	-*) echo "Unknown option: $1" >&2; break;;
	*) break;;
	esac
	shift
done

verify_git_settings

test -n "$INVALIDATE_NEXUS" &&
	verify_netrc_settings

pomVersion="$(sed -n 's/^	<version>\(.*\)-SNAPSHOT<\/version>$/\1/p' pom.xml)"
test $# = 1 || test ! -t 0 || {
	version=$pomVersion
	printf 'Version? [%s]: ' "$version"
	read line
	test -z "$line" || version="$line"
	set "$version"
}

test $# = 1 && test "a$1" = "a${1#-}" ||
die "Usage: $0 [--no-batch-mode] [--skip-push] [--alt-repository=<repository>] [--thirdparty=imagej] [--skip-gpg] [--extra-arg=<args>] <release-version>"

VERSION="$1"
REMOTE="${REMOTE:-origin}"

# do a quick sanity check on the new version number
case "$VERSION" in
[0-9]*)
	;;
*)
	die "Version '$VERSION' does not start with a digit!"
esac
valid_semver_bump "$pomVersion" "$VERSION"

# defaults

BASE_GAV="$(maven_helper gav-from-pom pom.xml)" ||
die "Could not obtain GAV coordinates for base project"

# If releasing to OSS Sonatype, enable some extra stuff
mvn -Dexec.executable='echo' -Dexec.args='${releaseProfiles}' exec:exec -q | grep -q 'sonatype-oss-release' &&
	verify_gpg_settings &&
	INVALIDATE_NEXUS=t

git update-index -q --refresh &&
git diff-files --quiet --ignore-submodules &&
git diff-index --cached --quiet --ignore-submodules HEAD -- ||
die "There are uncommitted changes!"

test refs/heads/master = "$(git rev-parse --symbolic-full-name HEAD)" ||
die "Not on 'master' branch"

HEAD="$(git rev-parse HEAD)" &&
git fetch "$REMOTE" master &&
FETCH_HEAD="$(git rev-parse FETCH_HEAD)" &&
test "$FETCH_HEAD" = HEAD ||
test "$FETCH_HEAD" = "$(git merge-base $FETCH_HEAD $HEAD)" ||
die "'master' is not up-to-date"

# Prepare new release without pushing (requires the release plugin >= 2.1)
$DRY_RUN mvn $BATCH_MODE release:prepare -DpushChanges=false -Dresume=false $TAG \
        $PROFILE $DEV_VERSION -DreleaseVersion="$VERSION" \
	"-Darguments=-Dgpg.skip=true ${EXTRA_ARGS# }" &&

# Squash the two commits on the current branch produced by the
# maven-release-plugin into one
test "[maven-release-plugin] prepare for next development iteration" = \
	"$(git show -s --format=%s HEAD)" ||
die "maven-release-plugin's commits are unexpectedly missing!"
$DRY_RUN git reset --soft HEAD^^ &&
if ! git diff-index --cached --quiet --ignore-submodules HEAD --
then
	$DRY_RUN git commit -s -m "Bump to next development cycle"
fi &&

# extract the name of the new tag
if test -z "$DRY_RUN"
then
	tag=$(sed -n 's/^scm.tag=//p' < release.properties)
else
	tag="<tag>"
fi &&

# rewrite the tag to include release.properties
test -n "$tag" &&
# HACK: SciJava projects use SSH (git@github.com:...) for developerConnection.
# The release:perform command wants to use the developerConnection URL when
# checking out the release tag. But reading from this URL requires credentials
# which we would rather Travis not need. So we replace the scm.url in the
# release.properties file to use the read-only (git://github.com/...) URL.
# This is OK, since release:perform does not need write access to the repo.
sed -i.bak -e 's|^scm.url=scm\\:git\\:git@github.com\\:|scm.url=scm\\:git\\:git\\://github.com/|' release.properties &&
rm release.properties.bak &&
$DRY_RUN git checkout "$tag" &&
$DRY_RUN git add release.properties &&
$DRY_RUN git commit --amend --no-edit &&
$DRY_RUN git tag -d "$tag" &&
$DRY_RUN git tag "$tag" HEAD &&
$DRY_RUN git checkout @{-1} &&

# push the current branch and the tag
if test -z "$SKIP_PUSH"
then
	$DRY_RUN git push "$REMOTE" HEAD $tag
fi ||
exit
