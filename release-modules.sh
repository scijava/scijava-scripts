#!/bin/sh

# ============================================================================
# release-modules.sh
# ============================================================================
# Releases several modules of a multi-module repository in succession.
#
# For each module, in the order given: runs release-version.sh without
# pushing, pushes only the new release tag, waits for CI to build and deploy
# that tag, and waits for the release to appear on Maven Central. The
# "Bump ... to next development cycle" commits stay local until every module
# is released, then the branch is pushed once, so that CI builds the branch
# only after all modules are released and consistent.
#
# Modules whose release tag already exists on the remote are not released
# again, but their CI and Maven Central checks still happen, so a failed run
# can be resumed by repeating the same command.
#
# Authors: Curtis Rueden
# ============================================================================

# -- Avoid localized output that might confuse the script --

export LC_ALL=C

# -- Constants --

CENTRAL=https://repo1.maven.org/maven2
CI_APPEAR_TIMEOUT=600
CENTRAL_POLL_INTERVAL=120
CENTRAL_TIMEOUT=7200

# -- Functions --

log() {
	echo "[release-modules] $(date '+%H:%M:%S') $*"
}

die() {
	echo "[release-modules] FAILED: $*" >&2
	test "$released" &&
		echo "[release-modules] Note: Bump commits for $released are not yet pushed.
Repeat the same command to resume, or push them with: git push $remote HEAD" >&2
	exit 1
}

# Prints the given POM expression for the project in the current directory.
pom_eval() {
	mvn -B -q -N help:evaluate -Dexpression="$1" -DforceStdout 2>/dev/null
}

# Waits for the CI run of the given tag to complete successfully, rerunning
# its failed jobs after a delay if they failed due to Maven Central throttling.
wait_for_ci() {
	log "Waiting for CI run on $1"
	run=
	elapsed=0
	while test -z "$run"
	do
		run=$(gh run list --branch "$1" --event push --limit 1 \
			--json databaseId -q '.[0].databaseId' 2>/dev/null)
		test "$run" && break
		test "$elapsed" -lt "$CI_APPEAR_TIMEOUT" || die "No CI run found for $1"
		sleep 10
		elapsed=$((elapsed + 10))
	done
	retries=0
	while :
	do
		log "Watching CI run $run"
		gh run watch "$run" --exit-status --interval 60 >/dev/null && break
		gh run view "$run" --log-failed 2>/dev/null | grep -q 'status code: 429' ||
			die "CI run $run failed for $1 (see: gh run view $run --log-failed)"
		test "$retries" -lt "$MAX_RETRIES" ||
			die "CI run $run for $1 was throttled by Maven Central $((retries + 1)) times"
		retries=$((retries + 1))
		log "CI run $run was throttled by Maven Central; rerunning in $RETRY_DELAY seconds"
		sleep "$RETRY_DELAY"
		gh run rerun "$run" --failed || die "Could not rerun CI run $run"
		# Note: Give the rerun time to register, so that we do not watch
		# the previous attempt, which has already completed.
		sleep 30
	done
	log "CI succeeded for $1"
}

# Waits for the given G:A:V to appear on Maven Central.
wait_for_central() {
	url="$CENTRAL/$(echo "$1" | tr . /)/$2/$3/$2-$3.pom"
	log "Waiting for $1:$2:$3 on Maven Central"
	elapsed=0
	until curl -fsI "$url" >/dev/null
	do
		test "$elapsed" -lt "$CENTRAL_TIMEOUT" ||
			die "$1:$2:$3 did not appear on Maven Central after $CENTRAL_TIMEOUT seconds"
		sleep "$CENTRAL_POLL_INTERVAL"
		elapsed=$((elapsed + CENTRAL_POLL_INTERVAL))
	done
	log "$1:$2:$3 is on Maven Central"
}

# -- Parse command line --

DELAY=600
RETRY_DELAY=1800
MAX_RETRIES=2
SKIP_PUSH=
USAGE=
modules=
while test $# -gt 0
do
	case "$1" in
	--delay=*) DELAY=${1#--*=};;
	--retry-delay=*) RETRY_DELAY=${1#--*=};;
	--max-retries=*) MAX_RETRIES=${1#--*=};;
	--skip-push) SKIP_PUSH=t;;
	--help) USAGE=t; break;;
	-*) echo "Unknown option: $1" >&2; USAGE=t; break;;
	*) modules="$modules $1";;
	esac
	shift
done

test -z "$modules" && USAGE=t
test "$USAGE" && {
	echo "Usage: $0 [options] <module>=<version> [<module>=<version> ...]

Where each <module> is a module directory of the multi-module repository
containing the current directory, or . for the root (aggregator) project,
and <version> is the version to release. The version is required, so that
repeating the same command after a failure resumes rather than releasing
already released modules again.

Options include:
  --delay=<seconds>       - Wait between modules, to spare Maven Central
                            (default: 600).
  --retry-delay=<seconds> - Wait before rerunning CI that was throttled by
                            Maven Central (default: 1800).
  --max-retries=<n>       - Rerun throttled CI at most this many times per
                            module (default: 2).
  --skip-push             - Do not push the branch after the last module.
" >&2
	exit 1
}

# -- Sanity checks --

command -v gh >/dev/null || die "The gh command is required."
rootDir=$(git rev-parse --show-toplevel) || die "Not in a git repository."
cd "$rootDir" || die "Could not change to $rootDir"
upstreamBranch=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}') ||
	die "The current branch has no upstream branch."
remote=${upstreamBranch%/*}
releaseVersion="$(cd "$(dirname "$0")" && pwd)/release-version.sh"
test -x "$releaseVersion" || die "Missing helper script at '$releaseVersion'"
for spec in $modules
do
	case "$spec" in
		*=?*) ;;
		*) die "No version given for module '$spec'" ;;
	esac
	test -f "${spec%%=*}/pom.xml" || die "No pom.xml in module '${spec%%=*}'"
done

# -- Release the modules --

released=
first=t
for spec in $modules
do
	module=${spec%%=*}
	version=${spec#*=}

	cd "$rootDir/$module" || die "Could not change to module '$module'"
	groupId=$(pom_eval project.groupId)
	artifactId=$(pom_eval project.artifactId)
	test "$groupId" -a "$artifactId" || die "Could not read coordinates of module '$module'"
	tag=$artifactId-$version

	if git ls-remote --exit-code --tags "$remote" "refs/tags/$tag" >/dev/null
	then
		log "$tag already exists on $remote; skipping its release"
	else
		test "$first" || {
			log "Waiting $DELAY seconds before the next release"
			sleep "$DELAY"
		}
		if git rev-parse -q --verify "refs/tags/$tag" >/dev/null
		then
			log "$tag already exists locally; pushing it"
		else
			log "=== Releasing $artifactId $version ==="
			"$releaseVersion" --skip-push "$version" </dev/null ||
				die "release-version.sh failed for $artifactId $version"
			git rev-parse -q --verify "refs/tags/$tag" >/dev/null ||
				die "release-version.sh did not create tag $tag"
			released="$released $artifactId"
		fi
		git push "$remote" "refs/tags/$tag" || die "Could not push tag $tag"

		# Note: Later modules depending on this one need its new SNAPSHOT
		# version to be resolvable, since release-version.sh reads their
		# project details before pinning their sibling dependencies to
		# releases. And the enforcer rejects SNAPSHOT dependencies, which
		# do not matter for this local install. If the install fails, a
		# later module needing it fails in release-version.sh before its
		# release begins, so we only warn here.
		log "Installing next SNAPSHOT of $artifactId locally"
		mvn -B -q -N install -DskipTests -Denforcer.skip ||
			log "WARNING: Local install of the next SNAPSHOT of $artifactId failed"
	fi
	first=

	wait_for_ci "$tag"
	wait_for_central "$groupId" "$artifactId" "$version"
done

# -- Push the branch --

cd "$rootDir" || die "Could not change to $rootDir"
if test "$SKIP_PUSH"
then
	log "All modules released; skipping push of the branch, as requested."
else
	log "All modules released; pushing the branch"
	git push "$remote" HEAD || die "Could not push the branch"
fi
