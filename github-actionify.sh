#!/bin/sh

# github-actionify.sh
#
# Script for enabling or updating GitHub Action builds for a given repository.

#set -e

dir="$(dirname "$0")"

gitactionDir=.github
gitactionConfig=.gitaction.yml
gitactionBuildScript=$gitactionDir/build.sh
gitactionSettingsFile=$gitactionDir/settings.xml
gitactionNotifyScript=$gitactionDir/notify.sh
credentialsDir=$HOME/.scijava/credentials
varsFile=$credentialsDir/vars
signingKeySourceFile=$credentialsDir/scijava-ci-signing.asc
signingKeyDestFile=$gitactionDir/signingkey.asc
pomMinVersion='17.1.1'
tmpFile=gitaction.tmp

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
	test "$msg" || msg="GitHub Action: update $file"
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
	$EXEC git diff-index --quiet HEAD -- || $EXEC git commit -m "$msg"
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

	######################### CHANGE POM.XML??? #########################
	# TODO:	2 sed statements to replace the system and the url under <ciManagement> in pom.xml
	#		<system>GitHub Actions<\system>
	#		<url>https://github.com/$repoSlug/actions<\url>
	# domain: manually assign to github.com and delete the rest
	domain=$(grep "travis-ci\.[a-z]*/$repoSlug" pom.xml 2>/dev/null | sed 's/.*\(travis-ci\.[a-z]*\).*/\1/')
	test "$domain" &&
		info "Detected domain from pom.xml: $domain" ||
		die "No valid ciManagement section in pom.xml. Please add one, then try again."

	case $domain in
		travis-ci.com) mode=pro;;
		travis-ci.org) mode=org;;
		*) die "Unsupported domain: $domain";;
	esac

	# -- GitHub Action sanity checks --

	test -e "$gitactionDir" -a ! -d "$gitactionDir" && die "$gitactionDir is not a directory"
	test -e "$gitactionConfig" -a ! -f "$gitactionConfig" && die "$gitactionConfig is not a regular file"
	test -e "$gitactionConfig" && warn "$gitactionConfig already exists"
	test -e "$gitactionBuildScript" && warn "$gitactionBuildScript already exists"

	# -- Do things --

	# Add/update the GitHun Actions configuration file.
	cat >"$tmpFile" <<EOL
language: java
jdk: openjdk8
branches:
  only:
  - $defaultBranch
  - "/.*-[0-9]+\\\\..*/"
install: true
script: "$gitactionBuildScript"
cache:
  directories:
  - "~/.m2/repository"
EOL
	update "$gitactionConfig"

	# Add/update the GitHub Action build script.
	cat >"$tmpFile" <<EOL
#!/bin/sh
curl -fsLO https://raw.githubusercontent.com/scijava/scijava-scripts/master/githun-action-build.sh
sh githun-action-build.sh
EOL
	chmod +x "$tmpFile"
	update "$githactionBuildScript" "GitHub Action: add executable script $gitactionBuildScript" "true"

	# Remove obsolete GitHub-Actions-related files.
	if [ -f "$gitactionSettingsFile" ]
	then
		info "Removing obsolete $gitactionSettingsFile (github-action-build.sh generates it now)"
		$EXEC git rm -f "$gitactionSettingsFile"
	fi
	if [ -f "$gitactionNotifyScript" ]
	then
		info "Removing obsolete $gitactionNotifyScript (ImageJ Jenkins is dead)"
		$EXEC git rm -f "$gitactionNotifyScript"
	fi
	$EXEC git diff-index --quiet HEAD -- || $EXEC git ci -m "GitHub Action: remove obsolete files"

	# Upgrade version of pom-scijava.
	if [ -z "$SKIP_PARENT_CHECK" ]
	then
		version=$(xmllint --xpath '//*[local-name()="project"]/*[local-name()="parent"]/*[local-name()="version"]' pom.xml|sed 's/[^>]*>//'|sed 's/<.*//')
		# HACK: Using a lexicographic comparison here is imperfect.
		if [ "$version" \< "$pomMinVersion" ]
		then
			info 'Upgrading pom-scijava version'
			sed "s|^		<version>$version</version>$|		<version>$pomMinVersion</version>|" pom.xml >"$tmpFile"
			update pom.xml "POM: update pom-scijava parent to $pomMinVersion"
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
		update pom.xml 'POM: deploy releases to the SciJava repository'
	fi

	# update the README
	# https://docs.github.com/en/actions/managing-workflow-runs/adding-a-workflow-status-badge
	if grep -q "github\.com/[a-zA-Z0-9/_-]*/actions/workflow/main.yml/badge.svg" README.md >/dev/null 2>&1
	then
		info "Updating README.md GitHub Action badge"
		sed "s|github\.com\/[a-zA-Z0-9/_-]*|$domain/$repoSlug|g" README.md >"$tmpFile"
		update README.md 'GitHub Action: fix README.md badge link'
	else
		info "Adding GitHub Action badge to README.md"
		echo "[![](https://$domain/$repoSlug.svg?branch=$defaultBranch)](https://$domain/$repoSlug)" >"$tmpFile"
		echo >>"$tmpFile"
		test -f README.md && cat README.md >>"$tmpFile"
		update README.md 'GitHub Action: add badge to README.md'
	fi

	# encrypt key/value pairs in variables file
	if [ -f "$varsFile" ]
	then
		while read p; do
			# Skip comments. (Cannot use ${p:0:1} because it's bash-specific.)
			case "$p" in
				'#'*) continue;;
			esac
			info "Encrypting ${p%%=*}"
			######################### TODO #########################
			yes | $EXEC travis encrypt --$mode "$p" --add env.global --repo "$repoSlug"
			test $? -eq 0 || die "Failed to encrypt variable '$p'"
		done <"$varsFile"
		$EXEC git commit "$gitactionConfig" -m "GitHub Action: add encrypted environment variables"
	else
		warn "No $varsFile found. GitHub Action will not have any environment variables set!"
	fi

	# encrypt GPG keypair
	if [ -f "$signingKeySourceFile" ]
	then
		info "Encrypting $signingKeyDestFile"
		if [ -z "$EXEC" ]
		then
			rm -f "$signingKeyDestFile.enc"
			######################### TODO #########################
			# https://docs.github.com/en/github/authenticating-to-github/generating-a-new-gpg-key
			encryptOutput=$(travis encrypt-file --$mode "$signingKeySourceFile" "$signingKeyDestFile.enc" --repo "$repoSlug")
			test $? -eq 0 || die "Failed to encrypt signing key."
			encryptResult=$(echo "$encryptOutput" | grep openssl)
			test "$encryptResult" || die "No openssl variables emitted."
			key=$(echo "$encryptResult" | cut -d' ' -f4)
			iv=$(echo "$encryptResult" | cut -d' ' -f6)
			sed -i.bak "s/\(sh github-action-build.sh\)/\1 $key $iv/" "$gitactionBuildScript"
			rm -f "$gitactionBuildScript.bak"
			git add "$gitactionBuildScript" "$signingKeyDestFile.enc"
			git commit -m "GitHub Action: add encrypted GPG signing keypair"
		fi
	else
		warn "No $signingKeySourceFile found. GitHub Action will not be able to do GPG signing!"
	fi
}

test -d "$credentialsDir" ||
	die "This script requires configuration stored in $credentialsDir,\n" \
		"including $varsFile for needed environment variables,\n" \
		"and $signingKeySourceFile for signing of artifacts.\n" \
		"Please contact a SciJava administrator to receive a copy of this content."

# check prerequisites
######################### TODO #########################
check git sed cut perl xmllint travis

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
