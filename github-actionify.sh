#!/bin/sh

# github-actionify.sh
#
# Script for enabling or updating GitHub Action builds for a given repository.

# Environment variables:
# 	$EXEC - an optional prefix for bash commands (for example, if $EXEC=sudo, then the commands will be run as super user access)
# 	$@ - all positional parameters
# 	$0, $1, ... - specific positional parameters for each method

#set -e

dir="$(dirname "$0")"

ciDir=.github
ciSlugBuildMain=workflows/build-main.yml
ciSlugBuildPR=workflows/build-pr.yml
ciConfigBuildMain=$ciDir/$ciSlugBuildMain
ciConfigBuildPR=$ciDir/$ciSlugBuildPR
ciSetupScript=$ciDir/setup.sh
ciBuildScript=$ciDir/build.sh
ciSettingsFile=$ciDir/settings.xml
ciNotifyScript=$ciDir/notify.sh
credentialsDir=$HOME/.scijava/credentials
varsFile=$credentialsDir/vars
pomMinVersion='17.1.1'
tmpFile=github-actionify.tmp
msgPrefix="CI: "

info() { echo "- $@"; }
warn() { echo "[WARNING] $@" 1>&2; }
err() { echo "[ERROR] $@" 1>&2; }
die() { err "$@"; exit 1; }

check() {
	for tool in $@
	do
		which "$tool" >/dev/null ||
			die "The '$tool' utility is required but not found"
	done
}

var() {
	grep "^$1=" "$varsFile" ||
		die "$1 not found in $varsFile"
}

update() {
	file=$1
	msg=$2
	exe=$3
	test "$msg" || msg="update $file"
	if [ -e "$file" ]
	then
		if diff -q "$file" "$tmpFile" >/dev/null
		then
			info "$file is already OK"
		else
			info "Updating $file"
			$EXEC rm -rf "$file"
			$EXEC mv -f "$tmpFile" "$file"
		fi
	else
		info "Creating $file"
		$EXEC mkdir -p "$(dirname "$file")"
		$EXEC mv "$tmpFile" "$file"
	fi
	rm -rf "$tmpFile"
	$EXEC git add "$file"
	if [ -n "$exe" ]
	then
		info "Adding execute permission to $file"
		$EXEC git update-index --chmod=+x "$file"
	fi
	$EXEC git diff-index --quiet HEAD -- || $EXEC git commit -m "$msgPrefix$msg"
}

process() {
	cd "$1"

	# -- Git sanity checks --

	repoSlug=$(xmllint --xpath '//*[local-name()="project"]/*[local-name()="scm"]/*[local-name()="connection"]' pom.xml|sed 's_.*github.com[:/]\(.*\)<.*_\1_')
	test "$repoSlug" && info "Repository = $repoSlug" || die 'Could not determine GitHub repository slug'
	case "$repoSlug" in
		*.git)
			die "GitHub repository slug ('$repoSlug') ends in '.git'; please fix the POM"
			;;
	esac
	git fetch >/dev/null
	git diff-index --quiet HEAD -- || die "Dirty working copy"
	currentBranch=$(git rev-parse --abbrev-ref HEAD)
	upstreamBranch=$(git rev-parse --abbrev-ref --symbolic-full-name @{u})
	remote=${upstreamBranch%/*}
	defaultBranch=$(git remote show "$remote" | grep "HEAD branch" | sed 's/.*: //')
	test "$currentBranch" = "$defaultBranch" || die "Non-default branch: $currentBranch"
	git merge --ff --ff-only 'HEAD@{u}' >/dev/null ||
		die "Cannot fast forward (local diverging?)"
#	test "$(git rev-parse HEAD)" = "$(git rev-parse 'HEAD@{u}')" ||
#		die "Mismatch with upstream branch (local ahead?)"

	# -- POM sanity checks --

	parent=$(xmllint --xpath '//*[local-name()="project"]/*[local-name()="parent"]/*[local-name()="artifactId"]' pom.xml|sed 's/[^>]*>//'|sed 's/<.*//')
	if [ -z "$SKIP_PARENT_CHECK" ]
	then
		test "$parent" = "pom-scijava" ||
			die "Not pom-scijava parent: $parent. Run with -p flag to skip this check."
	fi

	# Change pom.xml from Travis CI to GitHub Actions
	domain="github.com"
	sed 's/Travis CI/GitHub Actions/g' pom.xml >"$tmpFile"
	sed "s;travis-ci.*;github.com/$repoSlug/actions</url>;g" pom.xml >"$tmpFile"
	update pom.xml "switch from Travis CI to GitHub Actions"

	# -- GitHub Action sanity checks --

	test -e "$ciDir" -a ! -d "$ciDir" && die "$ciDir is not a directory"
	test -e "$ciConfigBuildMain" -a ! -f "$ciConfigBuildMain" && die "$ciConfigBuildMain is not a regular file"
	test -e "$ciConfigBuildPR" -a ! -f "$ciConfigBuildPR" && die "$ciConfigBuildPR is not a regular file"
	test -e "$ciConfigBuildMain" && warn "$ciConfigBuildMain already exists"
	test -e "$ciBuildScript" && warn "$ciBuildScript already exists"
	test -e "$ciSetupScript" && warn "$ciSetupScript already exists"

	# -- Do things --

	# Add/update the main GitHub Actions configuration file.
	cat >"$tmpFile" <<EOL
name: build

on:
  push:
    branches:
      - $defaultBranch

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - name: Cache m2 modules
        uses: actions/cache@v2
        env:
          cache-name: cache-node-modules
        with:
          path: ~/.m2
          key: \${{ runner.os }}-build-\${{ env.cache-name }}
          restore-keys: |
            \${{ runner.os }}-build-\${{ env.cache-name }}-
            \${{ runner.os }}-build-
            \${{ runner.os }}-

      - name: Set up JDK 8
        uses: actions/setup-java@v2
        with:
          java-version: '8'
          distribution: 'zulu'
      - name: Set up CI environment
        run: ./$ciSetupScript
      - name: Build with Maven
        run: ./$ciBuildScript
        env:
          GPG_KEY_NAME: \${{ secrets.GPG_KEY_NAME }}
          GPG_PASSPHRASE: \${{ secrets.GPG_PASSPHRASE }}
          MAVEN_USER: \${{ secrets.MAVEN_USER }}
          MAVEN_PASS: \${{ secrets.MAVEN_PASS }}
          OSSRH_PASS: \${{ secrets.OSSRH_PASS }}
          SIGNING_ASC: \${{ secrets.SIGNING_ASC }}
EOL
	update "$ciConfigBuildMain" "add/update main build action"

	# Add/update the GitHub Actions PR configuration file.
	cat >"$tmpFile" <<EOL
name: build PR

on:
  pull_request:
    branches:
      - $defaultBranch

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - name: Cache m2 modules
        uses: actions/cache@v2
        env:
          cache-name: cache-node-modules
        with:
          path: ~/.m2
          key: \${{ runner.os }}-build-\${{ env.cache-name }}
          restore-keys: |
            \${{ runner.os }}-build-\${{ env.cache-name }}-
            \${{ runner.os }}-build-
            \${{ runner.os }}-

      - name: Set up JDK 8
        uses: actions/setup-java@v2
        with:
          java-version: '8'
          distribution: 'zulu'
      - name: Set up CI environment
        run: ./$ciSetupScript
      - name: Build with Maven
        run: ./$ciBuildScript
EOL
	update "$ciConfigBuildPR" "add/update PR build action"

	# Add/update the GitHub Action setup script.
	cat >"$tmpFile" <<EOL
#!/bin/sh
curl -fsLO https://raw.githubusercontent.com/scijava/scijava-scripts/master/github-action-ci.sh
sh github-action-ci.sh
EOL
	chmod +x "$tmpFile"
	update "$ciSetupScript" "add executable script $ciSetupScript" "true"

	# Add/update the GitHub Action build script.
	cat >"$tmpFile" <<EOL
#!/bin/sh
curl -fsLO https://raw.githubusercontent.com/scijava/scijava-scripts/master/ci-build.sh
sh ci-build.sh
EOL
	chmod +x "$tmpFile"
	update "$ciBuildScript" "add executable script $ciBuildScript" "true"

	# Remove obsolete GitHub-Actions-related files.
	if [ -f "$ciSettingsFile" ]
	then
		info "Removing obsolete $ciSettingsFile (github-action-build.sh generates it now)"
		$EXEC git rm -f "$ciSettingsFile"
	fi
	if [ -f "$ciNotifyScript" ]
	then
		info "Removing obsolete $ciNotifyScript (ImageJ Jenkins is dead)"
		$EXEC git rm -f "$ciNotifyScript"
	fi
	$EXEC git diff-index --quiet HEAD -- || $EXEC git commit -m "${msgPrefix}remove obsolete files"

	# Upgrade version of pom-scijava.
	if [ -z "$SKIP_PARENT_CHECK" ]
	then
		version=$(xmllint --xpath '//*[local-name()="project"]/*[local-name()="parent"]/*[local-name()="version"]' pom.xml|sed 's/[^>]*>//'|sed 's/<.*//')
		# HACK: Using a lexicographic comparison here is imperfect.
		if [ "$version" \< "$pomMinVersion" ]
		then
			info 'Upgrading pom-scijava version'
			sed "s|^		<version>$version</version>$|		<version>$pomMinVersion</version>|" pom.xml >"$tmpFile"
			update pom.xml "update pom-scijava parent to $pomMinVersion"
		else
			info "Version of pom-scijava ($version) is OK"
		fi
	fi

	# ensure <releaseProfiles> section is present
	releaseProfile=$(grep '<releaseProfiles>' pom.xml 2>/dev/null | sed 's/[^>]*>//' | sed 's/<.*//')
	if [ "$releaseProfile" ]
	then
		test "$releaseProfile" = 'deploy-to-scijava' ||
			warn "Unknown release profile: $releaseProfile"
	else
		info 'Adding <releaseProfiles> property'
		cp pom.xml "$tmpFile"
		perl -0777 -i -pe 's/(\n\t<\/properties>\n)/\n\n\t\t<!-- NB: Deploy releases to the SciJava Maven repository. -->\n\t\t<releaseProfiles>deploy-to-scijava<\/releaseProfiles>\1/igs' "$tmpFile"
		update pom.xml 'deploy releases to the SciJava repository'
	fi

	# update the README
	# https://docs.github.com/en/actions/managing-workflow-runs/adding-a-workflow-status-badge
	if grep -q "travis-ci.*svg" README.md >/dev/null 2>&1
	then
		info "Updating README.md GitHub Action badge"
		sed "s;travis-ci.*;$domain/$repoSlug/actions/$ciSlugBuildMain/badge.svg)](https://$domain/$repoSlug/actions/$ciSlugBuildMain);g" README.md >"$tmpFile"
		update README.md 'update README.md badge link'
	else
		info "Adding GitHub Action badge to README.md"
		echo "[![](https://$domain/$repoSlug/actions/$ciSlugBuildMain/badge.svg)](https://$domain/$repoSlug/actions/$ciSlugBuildMain)" >"$tmpFile"
		echo >>"$tmpFile"
		test -f README.md && cat README.md >>"$tmpFile"
		update README.md 'add README.md badge link'
	fi
}

cat <<EOL
---------------------------------------------------------------------
This script sets up continuous integration (CI) using GitHub Actions.
It will add CI configuration if none is present, or update it to the
latest best practices otherwise. Note that for your project to deploy
build artifacts to maven.scijava.org or oss.sonatype.org, deployment
credentials must be available during the CI build; contact a SciJava
administrator via https://forum.image.sc/ to request them be added as
secrets to your GitHub organization if they aren't already present.
---------------------------------------------------------------------
EOL

# call check method to verify prerequisites
check git sed cut perl xmllint

# parse arguments
EXEC=:
SKIP_PARENT_CHECK=
while test $# -gt 0
do
	case "$1" in
	-f) EXEC=;;
	-p) SKIP_PARENT_CHECK=true;;
	--) break;;
	-*) echo "Ignoring unknown option: $1" >&2; break;;
	*) break;;
	esac
	shift
done

test "$EXEC" && warn "Simulation only. Run with -f flag to go for real."

# process arguments
if [ $# -gt 0 ]
then
	for d in $@
	do (
		echo "[$d]"
		process "$d"
	) done
else
	process .
fi
