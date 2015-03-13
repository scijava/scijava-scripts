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

IMAGEJ_BASE_REPOSITORY=-DaltDeploymentRepository=imagej.releases::default::dav:http://maven.imagej.net/content/repositories
IMAGEJ_RELEASES_REPOSITORY=$IMAGEJ_BASE_REPOSITORY/releases
IMAGEJ_THIRDPARTY_REPOSITORY=$IMAGEJ_BASE_REPOSITORY/thirdparty

BATCH_MODE=--batch-mode
SKIP_PUSH=
SKIP_DEPLOY=
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
	--skip-deploy) SKIP_DEPLOY=t;;
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

test $# = 1 || test ! -t 0 || {
	version="$(sed -n 's/^	<version>\(.*\)-SNAPSHOT<\/version>$/\1/p' \
		pom.xml)"
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

# defaults

BASE_GAV="$(maven_helper gav-from-pom pom.xml)" ||
die "Could not obtain GAV coordinates for base project"

case "$BASE_GAV" in
net.imagej:imagej-launcher:*)
	SKIP_DEPLOY=t
	;;
org.scijava:pom-jython-shaded:*)
	ARTIFACT_ID=${BASE_GAV#*:pom-}
	ARTIFACT_ID=${ARTIFACT_ID%:*}
	test -n "$TAG" || TAG=-Dtag=$ARTIFACT_ID-$VERSION
	test -n "$GPG_KEYNAME" || die "Need to set GPG_KEYNAME"
	test -n "$GPG_PASSPHRASE" || die "Need to set GPG_PASSPHRASE"
	PROFILE=-Psonatype-oss-release
	INVALIDATE_NEXUS=t
	;;
com.github.maven-nar:nar-maven-plugin:*|\
io.scif:pom-scifio:*|\
net.imagej:ij1-patcher:*|\
net.imagej:imagej-maven-plugin:*|\
net.imagej:pom-imagej:*|\
net.imglib2:imglib2:*|\
net.imglib2:pom-imglib2:*|\
org.scijava:jep:*|\
org.scijava:junit-benchmarks:*|\
org.scijava:minimaven:*|\
org.scijava:native-lib-loader:*|\
org.scijava:pom-scijava:*|\
org.scijava:scijava-common:*|\
org.scijava:scijava-expression-parser:*|\
org.scijava:scijava-log-slf4j:*|\
org.scijava:scijava-maven-plugin:*|\
org.scijava:swing-checkbox-tree:*)
	test -n "$GPG_KEYNAME" || die "Need to set GPG_KEYNAME"
	test -n "$GPG_PASSPHRASE" || die "Need to set GPG_PASSPHRASE"
	PROFILE=-Psonatype-oss-release
	INVALIDATE_NEXUS=t
	;;
*:pom-fiji:*)
	;;
*:pom-*:*)
	ARTIFACT_ID=${BASE_GAV#*:pom-}
	ARTIFACT_ID=${ARTIFACT_ID%:*}
	test -n "$TAG" || TAG=-Dtag=$ARTIFACT_ID-$VERSION
esac

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

# push the current branch and the tag
if test -z "$DRY_RUN"
then
	tag=$(sed -n 's/^scm.tag=//p' < release.properties)
else
	tag="<tag>"
fi &&
test -n "$tag" &&
if test -z "$SKIP_PUSH"
then
	$DRY_RUN git push "$REMOTE" HEAD &&
	$DRY_RUN git push "$REMOTE" $tag
fi ||
exit

if test -z "$SKIP_DEPLOY"
then
	$DRY_RUN git checkout $tag &&
	$DRY_RUN mvn $PROFILE \
		-Dgpg.keyname="$GPG_KEYNAME" \
		-Dgpg.passphrase="$GPG_PASSPHRASE" \
		-DperformRelease \
		clean verify &&
	$DRY_RUN mvn $PROFILE \
		-Dgpg.keyname="$GPG_KEYNAME" \
		-Dgpg.passphrase="$GPG_PASSPHRASE" \
		$ALT_REPOSITORY \
		-DperformRelease -DupdateReleaseInfo=true \
		deploy &&
	$DRY_RUN git checkout @{-1}
	if test -n "$INVALIDATE_NEXUS"
	then
		$DRY_RUN maven_helper invalidate-cache "${BASE_GAV%:*}"
	fi
fi
