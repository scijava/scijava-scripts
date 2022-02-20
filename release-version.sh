#!/bin/sh

# ============================================================================
# release-version.sh
# ============================================================================
# Releases a new version of a component extending the pom-scijava parent.
#
# Authors: Johannes Schindelin & Curtis Rueden
# ============================================================================

# -- Avoid localized output that might confuse the script --

export LC_ALL=C

# -- Functions --

die () {
	echo "$*" >&2
	exit 1
}

no_changes_pending() {
	git update-index -q --refresh &&
	git diff-files --quiet --ignore-submodules &&
	git diff-index --cached --quiet --ignore-submodules HEAD --
}

# -- Constants and settings --

SCIJAVA_BASE_REPOSITORY=-DaltDeploymentRepository=scijava.releases::default::dav:https://maven.scijava.org/content/repositories
SCIJAVA_RELEASES_REPOSITORY=$SCIJAVA_BASE_REPOSITORY/releases
SCIJAVA_THIRDPARTY_REPOSITORY=$SCIJAVA_BASE_REPOSITORY/thirdparty

# Parse command line options.
BATCH_MODE=--batch-mode
SKIP_VERSION_CHECK=
SKIP_BRANCH_CHECK=
SKIP_LICENSE_UPDATE=
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
	--skip-branch-check) SKIP_BRANCH_CHECK=t;;
	--skip-license-update) SKIP_LICENSE_UPDATE=t;;
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
  --skip-version-check    - Skips the SemVer and parent pom version checks.
  --skip-branch-check     - Skips the default branch check.
  --skip-license-update   - Skips update of the copyright blurbs.
  --skip-push             - Do not push to the remote git repository.
  --dev-version=<x.y.z>   - Specify next development version explicitly;
                            e.g.: if you release 2.0.0-beta-1, by default
                            Maven will set the next development version at
                            2.0.0-beta-2-SNAPSHOT, but maybe you want to
                            set it to 2.0.0-SNAPSHOT instead.
  --alt-repository=<repo> - Deploy release to a different remote repository.
  --skip-gpg              - Do not perform GPG signing of artifacts.
"

# -- Extract project details --

projectDetails=$(mvn -N -Dexec.executable='echo' -Dexec.args='${project.version}:${license.licenseName}:${project.parent.groupId}:${project.parent.artifactId}:${project.parent.version}' exec:exec -q)
test $? -eq 0 || die "Could not extract version from pom.xml. Error follows:\n$projectDetails"
currentVersion=${projectDetails%%:*}
projectDetails=${projectDetails#*:}
licenseName=${projectDetails%%:*}
parentGAV=${projectDetails#*:}

# -- Sanity checks --

# Check that we have push rights to the repository.
if [ ! "$SKIP_PUSH" ]
then
	push=$(git remote -v | grep origin | grep '(push)')
	test "$push" || die 'No push URL found for remote origin.
Please use "git remote -v" to double check your remote settings.'
	echo "$push" | grep -q 'git:/' && die 'Remote origin is read-only.
Please use "git remote set-url origin ..." to change it.'
fi

# Discern the version to release.
pomVersion=${currentVersion%-SNAPSHOT}
test "$VERSION" || test ! -t 0 || {
	printf 'Version? [%s]: ' "$pomVersion"
	read VERSION
	test "$VERSION" || VERSION=$pomVersion
}

# Check that the release version number starts with a digit.
test "$VERSION" || die 'Please specify the version to release!'
test "$SKIP_VERSION_CHECK" || {
	case "$VERSION" in
	[0-9]*)
		;;
	*)
		die "Version '$VERSION' does not start with a digit!
If you are sure, try again with --skip-version-check flag."
	esac
}

# Check that the release version number conforms to SemVer.
VALID_SEMVER_BUMP="$(cd "$(dirname "$0")" && pwd)/valid-semver-bump.sh"
test -f "$VALID_SEMVER_BUMP" ||
	die "Missing helper script at '$VALID_SEMVER_BUMP'
Do you have a full clone of https://github.com/scijava/scijava-scripts?"
test "$SKIP_VERSION_CHECK" || {
	sh -$- "$VALID_SEMVER_BUMP" "$pomVersion" "$VERSION" ||
		die "If you are sure, try again with --skip-version-check flag."
}

# Check that the project extends the latest version of pom-scijava.
MAVEN_HELPER="$(cd "$(dirname "$0")" && pwd)/maven-helper.sh"
test -f "$MAVEN_HELPER" ||
	die "Missing helper script at '$MAVEN_HELPER'
Do you have a full clone of https://github.com/scijava/scijava-scripts?"
test "$SKIP_VERSION_CHECK" -o "$parentGAV" != "${parentGAV#$}" || {
	latestParentVersion=$(sh -$- "$MAVEN_HELPER" latest-version "$parentGAV")
	currentParentVersion=${parentGAV##*:}
	test "$currentParentVersion" = "$latestParentVersion" ||
		die "Newer version of parent '${parentGAV%:*}' is available: $latestParentVersion.
I recommend you update it before releasing.
Or if you know better, try again with --skip-version-check flag."
}

# Check that the working copy is clean.
no_changes_pending || die 'There are uncommitted changes!'
test -z "$(git ls-files -o --exclude-standard)" ||
	die 'There are untracked files! Please stash them before releasing.'

# Discern default branch.
currentBranch=$(git rev-parse --abbrev-ref --symbolic-full-name HEAD)
upstreamBranch=$(git rev-parse --abbrev-ref --symbolic-full-name @{u})
remote=${upstreamBranch%/*}
defaultBranch=$(git remote show "$remote" | grep "HEAD branch" | sed 's/.*: //')

# Check that we are on the main branch.
test "$SKIP_BRANCH_CHECK" || {
	test "$currentBranch" = "$defaultBranch" || die "Non-default branch: $currentBranch.
If you are certain you want to release from this branch,
try again with --skip-branch-check flag."
}

# If REMOTE is unset, use branch's upstream remote by default.
REMOTE="${REMOTE:-$remote}"

# Check that the main branch isn't behind the upstream branch.
HEAD="$(git rev-parse HEAD)" &&
git fetch "$REMOTE" "$defaultBranch" &&
FETCH_HEAD="$(git rev-parse FETCH_HEAD)" &&
test "$FETCH_HEAD" = HEAD ||
test "$FETCH_HEAD" = "$(git merge-base $FETCH_HEAD $HEAD)" ||
	die "'$defaultBranch' is not up-to-date"

# Ensure that schema location URL uses HTTPS, not HTTP.
if grep -q http://maven.apache.org/xsd/maven-4.0.0.xsd pom.xml >/dev/null 2>/dev/null
then
	echo "====================================================================="
	echo "NOTE: Your POM's schema location uses HTTP, not HTTPS. Fixing it now."
	echo "====================================================================="
	sed 's;http://maven.apache.org/xsd/maven-4.0.0.xsd;https://maven.apache.org/xsd/maven-4.0.0.xsd;' pom.xml > pom.new &&
	mv -f pom.new pom.xml &&
	git commit pom.xml \
		-m 'POM: use HTTPS for schema location URL' \
		-m 'Maven no longer supports plain HTTP for the schema location.' \
		-m 'And using HTTP now generates errors in Eclipse (and probably other IDEs).'
fi

# Ensure license headers are up-to-date.
test "$SKIP_LICENSE_UPDATE" -o -z "$licenseName" -o "$licenseName" = "N/A" || {
	mvn license:update-project-license license:update-file-header &&
	git add LICENSE.txt || die 'Failed to update copyright blurbs.
You can skip the license update using the --skip-license-update flag.'
	no_changes_pending ||
		die 'Copyright blurbs needed an update -- commit changes and try again.
Or if the license headers are being added erroneously to certain files,
exclude them by setting license.excludes in your POM; e.g.:

   <license.excludes>**/script_templates/**</license.excludes>

Alternately, try again with the --skip-license-update flag.'
}

# Prepare new release without pushing (requires the release plugin >= 2.1).
$DRY_RUN mvn $BATCH_MODE release:prepare -DpushChanges=false -Dresume=false $TAG \
        $PROFILE $DEV_VERSION -DreleaseVersion="$VERSION" \
	"-Darguments=-Dgpg.skip=true ${EXTRA_ARGS# }" ||
	die 'The release preparation step failed -- look above for errors and fix them.
Use "mvn javadoc:javadoc | grep error" to check for javadoc syntax errors.'

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
# release.properties file to use the public (https://github.com/...) URL.
# This is OK, since release:perform does not need write access to the repo.
$DRY_RUN sed -i.bak -e 's|^scm.url=scm\\:git\\:git@github.com\\:|scm.url=scm\\:git\\:https\\://github.com/|' release.properties &&
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
