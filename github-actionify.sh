#!/bin/sh

# github-actionify.sh
#
# Script for enabling or updating GitHub Action builds for a given repository.

#set -e

dir="$(dirname "$0")"

ciDir=.github
ciSlugBuild=workflows/build.yml
ciConfigBuild=$ciDir/$ciSlugBuild
ciSetupScript=$ciDir/setup.sh
ciBuildScript=$ciDir/build.sh
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

	repoSlug=$(grep '<connection>' pom.xml | sed 's;.*github.com[/:]\(.*/.*\)</connection>.*;\1;')
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
	defaultBranch=$(git remote show "$remote" | grep "HEAD" | sed 's/.*: //')
	test "$currentBranch" = "$defaultBranch" || die "Non-default branch: $currentBranch"
	git merge --ff --ff-only 'HEAD@{u}' >/dev/null ||
		die "Cannot fast forward (local diverging?)"
#	test "$(git rev-parse HEAD)" = "$(git rev-parse 'HEAD@{u}')" ||
#		die "Mismatch with upstream branch (local ahead?)"

	# -- POM sanity checks --

	parent=$(grep -A4 '<parent>' pom.xml | grep '<artifactId>' | sed 's;.*<artifactId>\(.*\)</artifactId>.*;\1;')
	if [ -z "$SKIP_PARENT_CHECK" ]
	then
		test "$parent" = "pom-scijava" ||
			die "Not pom-scijava parent: $parent. Run with -p flag to skip this check."
	fi

	# Change pom.xml from Travis CI to GitHub Actions
	domain="github.com"
	sed 's/Travis CI/GitHub Actions/g' pom.xml |
		sed "s;travis-ci.*;github.com/$repoSlug/actions</url>;g" >"$tmpFile"
	update pom.xml "switch from Travis CI to GitHub Actions"

	# -- GitHub Action sanity checks --

	test -e "$ciDir" -a ! -d "$ciDir" && die "$ciDir is not a directory"
	test -e "$ciConfigBuild" -a ! -f "$ciConfigBuild" && die "$ciConfigBuild is not a regular file"
	test -e "$ciConfigBuild" && warn "$ciConfigBuild already exists"
	test -e "$ciBuildScript" && warn "$ciBuildScript already exists"
	test -e "$ciSetupScript" && warn "$ciSetupScript already exists"

	# -- GitHub Action steps --

	actionCheckout="uses: actions/checkout@v2"
	actionSetupJava="name: Set up Java
        uses: actions/setup-java@v3
        with:
          java-version: '8'
          distribution: 'zulu'
          cache: 'maven'"
	actionSetupConda="name: Set up conda
        uses: s-weigand/setup-conda@v1
      - name: Install conda packages
        run: conda env update -f environment.yml -n base"
	actionSetupCI="name: Set up CI environment
        run: $ciSetupScript"
	actionExecuteBuild="name: Execute the build
        run: $ciBuildScript"
  actionSecrets="env:
          GPG_KEY_NAME: \${{ secrets.GPG_KEY_NAME }}
          GPG_PASSPHRASE: \${{ secrets.GPG_PASSPHRASE }}
          MAVEN_USER: \${{ secrets.MAVEN_USER }}
          MAVEN_PASS: \${{ secrets.MAVEN_PASS }}
          CENTRAL_USER: \${{ secrets.CENTRAL_USER }}
          CENTRAL_PASS: \${{ secrets.CENTRAL_PASS }}
          SIGNING_ASC: \${{ secrets.SIGNING_ASC }}"

	# -- Do things --

	# Add/update the GitHub Actions build configuration file.
	cat >"$tmpFile" <<EOL
name: build

on:
  push:
    branches:
      - $defaultBranch
    tags:
      - "*-[0-9]+.*"
  pull_request:
    branches:
      - $defaultBranch

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - $actionCheckout
      - $actionSetupJava
EOL
	test -f environment.yml && echo "      - $actionSetupConda" >>"$tmpFile"
	cat >>"$tmpFile" <<EOL
      - $actionSetupCI
      - $actionExecuteBuild
        $actionSecrets
EOL
	update "$ciConfigBuild" "add/update build action"

	# Add/update the GitHub Actions setup script.
	cat >"$tmpFile" <<EOL
#!/bin/sh
curl -fsLO https://raw.githubusercontent.com/scijava/scijava-scripts/main/ci-setup-github-actions.sh
sh ci-setup-github-actions.sh
EOL
	chmod +x "$tmpFile"
	update "$ciSetupScript" "add executable script $ciSetupScript" "true"

	# Add/update the GitHub Actions build script.
	cat >"$tmpFile" <<EOL
#!/bin/sh
curl -fsLO https://raw.githubusercontent.com/scijava/scijava-scripts/main/ci-build.sh
sh ci-build.sh
EOL
	chmod +x "$tmpFile"
	update "$ciBuildScript" "add executable script $ciBuildScript" "true"

	# Upgrade version of pom-scijava.
	if [ -z "$SKIP_PARENT_CHECK" ]
	then
		version=$(grep -A4 '<parent>' pom.xml | grep '<version>' | sed 's;.*<version>\(.*\)</version>.*;\1;')
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
		case "$releaseProfile" in
			sign,deploy-to-scijava)
				info 'No changes needed to <releaseProfiles> property'
				;;
			deploy-to-scijava)
				info 'Updating <releaseProfiles> property'
				sed 's;\(<releaseProfiles>\).*\(</releaseProfiles>\);\1sign,deploy-to-scijava\2;' pom.xml >"$tmpFile"
				update pom.xml 'sign JARs when deploying releases'
				;;
			*)
				warn "Unknown release profile: $releaseProfile"
				;;
		esac
	else
		info 'Adding <releaseProfiles> property'
		cp pom.xml "$tmpFile"
		perl -0777 -i -pe 's/(\n\t<\/properties>\n)/\n\n\t\t<!-- NB: Deploy releases to the SciJava Maven repository. -->\n\t\t<releaseProfiles>sign,deploy-to-scijava<\/releaseProfiles>\1/igs' "$tmpFile"
		update pom.xml 'deploy releases to the SciJava repository'
	fi

	# update the README
	# https://docs.github.com/en/actions/managing-workflow-runs/adding-a-workflow-status-badge
	if grep -q "travis-ci.*svg" README.md >/dev/null 2>&1
	then
		info "Updating README.md GitHub Action badge"
		sed "s;travis-ci.*;$domain/$repoSlug/actions/$ciSlugBuild/badge.svg)](https://$domain/$repoSlug/actions/$ciSlugBuild);g" README.md >"$tmpFile"
		update README.md 'update README.md badge link'
	elif grep -qF "$domain/$repoSlug/actions/$ciSlugBuild/badge.svg" README.md >/dev/null 2>&1
	then
		info "GitHub Action badge already present in README.md"
	else
		info "Adding GitHub Action badge to README.md"
		echo "[![Build Status](https://$domain/$repoSlug/actions/$ciSlugBuild/badge.svg)](https://$domain/$repoSlug/actions/$ciSlugBuild)" >"$tmpFile"
		echo >>"$tmpFile"
		test -f README.md && cat README.md >>"$tmpFile"
		update README.md 'add README.md badge link'
	fi

	# remove old Travis CI configuration
	test ! -e .travis.yml || $EXEC git rm -rf .travis.yml
	test ! -e .travis || $EXEC git rm -rf .travis
	$EXEC git diff-index --quiet HEAD -- &&
		info "No old CI configuration to remove." ||
		$EXEC git commit -m "${msgPrefix}remove Travis CI configuration"
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
check git grep sed perl

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
