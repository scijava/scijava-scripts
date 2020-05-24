#!/bin/sh

# ============================================================================
# release-version.sh
# ============================================================================
# Releases a new version of a component extending the pom-scijava parent.
#
# Authors: Johannes Schindelin & Curtis Rueden
# ============================================================================

# -- Functions --

die () {
	echo "$*" >&2
	exit 1
}

# -- Constants and settings --

SCIJAVA_BASE_REPOSITORY=-DaltDeploymentRepository=scijava.releases::default::dav:https://maven.scijava.org/content/repositories
SCIJAVA_RELEASES_REPOSITORY=$SCIJAVA_BASE_REPOSITORY/releases
SCIJAVA_THIRDPARTY_REPOSITORY=$SCIJAVA_BASE_REPOSITORY/thirdparty

# Parse command line options.
BATCH_MODE=--batch-mode
SKIP_VERSION_CHECK=
SKIP_PUSH=
SKIP_GPG=
TAG=
DEV_VERSION=
EXTRA_ARGS=
ALT_REPOSITORY=
PROFILE=-Pdeploy-to-scijava
DRY_RUN=
USAGE=
VERSION=
while test $# -gt 0
do
	case "$1" in
	--dry-run) DRY_RUN=echo;;
	--no-batch-mode) BATCH_MODE=;;
	--skip-version-check) SKIP_VERSION_CHECK=t;;
	--skip-push) SKIP_PUSH=t;;
	--tag=*)
		! git rev-parse --quiet --verify refs/tags/"${1#--*=}" ||
		die "Tag ${1#--*=} exists already!"
		TAG="-Dtag=${1#--*=}";;
	--dev-version=*|--development-version=*)
		DEV_VERSION="-DdevelopmentVersion=${1#--*=}";;
	--extra-arg=*|--extra-args=*)
		EXTRA_ARGS="$EXTRA_ARGS ${1#--*=}";;
	--alt-repository=scijava-releases)
		ALT_REPOSITORY=$SCIJAVA_RELEASES_REPOSITORY;;
	--alt-repository=scijava-thirdparty)
		ALT_REPOSITORY=$SCIJAVA_THIRDPARTY_REPOSITORY;;
	--alt-repository=*|--alt-deployment-repository=*)
		ALT_REPOSITORY="${1#--*=}";;
	--skip-gpg)
		SKIP_GPG=t
		EXTRA_ARGS="$EXTRA_ARGS -Dgpg.skip=true";;
	--help)
		USAGE=t
		break;;
	-*)
		echo "Unknown option: $1" >&2
		USAGE=t
		break;;
	*)
		test -z "$VERSION" || {
			echo "Extraneous argument: $1" >&2
			USAGE=t
			break
		}
		VERSION=$1;;
	esac
	shift
done

test "$USAGE" &&
die "Usage: $0 [options] [<version>]

Where <version> is the version to release. If omitted, it will prompt you.

Options include:
  --dry-run               - Simulate the release without actually doing it.
  --skip-version-check    - Violate SemVer version numbering intentionally.
  --skip-push             - Do not push to the remote git repository.
  --dev-version=<x.y.z>   - Specify next development version explicitly;
                            e.g.: if you release 2.0.0-beta-1, by default
                            Maven will set the next development version at
                            2.0.0-beta-2-SNAPSHOT, but maybe you want to
                            set it to 2.0.0-SNAPSHOT instead.
  --alt-repository=<repo> - Deploy release to a different remote repository.
  --skip-gpg              - Do not perform GPG signing of artifacts.
"

# -- Sanity checks --

# Check that we have push rights to the repository.
if [ ! "$SKIP_PUSH" ]
then
	push=$(git remote -v | grep origin | grep '(push)')
	test "$push" || die 'No push URL found for remote origin'
	echo "$push" | grep -q 'git:/' && die 'Remote origin is read-only'
fi

# Discern the version to release.
currentVersion=$(mvn -N -Dexec.executable='echo' -Dexec.args='${project.version}' exec:exec -q)
pomVersion=${currentVersion%-SNAPSHOT}
test "$VERSION" || test ! -t 0 || {
	printf 'Version? [%s]: ' "$pomVersion"
	read VERSION
	test "$VERSION" || VERSION=$pomVersion
}

# If REMOTE is unset, use origin by default.
REMOTE="${REMOTE:-origin}"

# Check that the release version number starts with a digit.
test "$VERSION" || die 'Please specify the version to release!'
case "$VERSION" in
[0-9]*)
	;;
*)
	die "Version '$VERSION' does not start with a digit!"
esac

# Check that the release version number conforms to SemVer.
VALID_SEMVER_BUMP="$(cd "$(dirname "$0")" && pwd)/valid-semver-bump.sh"
test -f "$VALID_SEMVER_BUMP" ||
	die "Missing helper script at '$VALID_SEMVER_BUMP'"
test "$SKIP_VERSION_CHECK" || {
	sh -$- "$VALID_SEMVER_BUMP" "$pomVersion" "$VERSION" || die
}

# Check that the working copy is clean.
git update-index -q --refresh &&
git diff-files --quiet --ignore-submodules &&
git diff-index --cached --quiet --ignore-submodules HEAD -- ||
die "There are uncommitted changes!"

# Check that we are on the master branch.
test refs/heads/master = "$(git rev-parse --symbolic-full-name HEAD)" ||
die "Not on 'master' branch"

# Check that the master branch isn't behind the upstream branch.
HEAD="$(git rev-parse HEAD)" &&
git fetch "$REMOTE" master &&
FETCH_HEAD="$(git rev-parse FETCH_HEAD)" &&
test "$FETCH_HEAD" = HEAD ||
test "$FETCH_HEAD" = "$(git merge-base $FETCH_HEAD $HEAD)" ||
die "'master' is not up-to-date"

# Prepare new release without pushing (requires the release plugin >= 2.1).
$DRY_RUN mvn $BATCH_MODE release:prepare -DpushChanges=false -Dresume=false $TAG \
        $PROFILE $DEV_VERSION -DreleaseVersion="$VERSION" \
	"-Darguments=-Dgpg.skip=true ${EXTRA_ARGS# }" &&

# Squash the maven-release-plugin's two commits into one.
if test -z "$DRY_RUN"
then
	test "[maven-release-plugin] prepare for next development iteration" = \
		"$(git show -s --format=%s HEAD)" ||
	die "maven-release-plugin's commits are unexpectedly missing!"
fi
$DRY_RUN git reset --soft HEAD^^ &&
if ! git diff-index --cached --quiet --ignore-submodules HEAD --
then
	$DRY_RUN git commit -s -m "Bump to next development cycle"
fi &&

# Extract the name of the new tag.
if test -z "$DRY_RUN"
then
	tag=$(sed -n 's/^scm.tag=//p' < release.properties)
else
	tag="<tag>"
fi &&

# Rewrite the tag to include release.properties.
test -n "$tag" &&
# HACK: SciJava projects use SSH (git@github.com:...) for developerConnection.
# The release:perform command wants to use the developerConnection URL when
# checking out the release tag. But reading from this URL requires credentials
# which we would rather Travis not need. So we replace the scm.url in the
# release.properties file to use the read-only (git://github.com/...) URL.
# This is OK, since release:perform does not need write access to the repo.
$DRY_RUN sed -i.bak -e 's|^scm.url=scm\\:git\\:git@github.com\\:|scm.url=scm\\:git\\:git\\://github.com/|' release.properties &&
$DRY_RUN rm release.properties.bak &&
$DRY_RUN git checkout "$tag" &&
$DRY_RUN git add -f release.properties &&
$DRY_RUN git commit --amend --no-edit &&
$DRY_RUN git tag -d "$tag" &&
$DRY_RUN git tag "$tag" HEAD &&
$DRY_RUN git checkout @{-1} &&

# Push the current branch and the tag.
if test -z "$SKIP_PUSH"
then
	$DRY_RUN git push "$REMOTE" HEAD $tag
fi ||
exit
