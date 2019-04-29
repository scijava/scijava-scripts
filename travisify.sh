#!/bin/sh

# travisify.sh
#
# Script for enabling or updating Travis CI builds for a given repository.

#set -e

dir="$(dirname "$0")"

travisDir=.travis
travisConfig=.travis.yml
travisBuildScript=$travisDir/build.sh
travisSettingsFile=$travisDir/settings.xml
travisNotifyScript=$travisDir/notify.sh
credentialsDir=$HOME/.scijava/credentials
varsFile=$credentialsDir/vars
signingKeySourceFile=$credentialsDir/scijava-ci-signing.asc
signingKeyDestFile=$travisDir/signingkey.asc
pomMinVersion='17.1.1'
tmpFile=travisify.tmp

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
	test "$msg" || msg="Travis: update $file"
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
	branch=$(git rev-parse --abbrev-ref HEAD)
	test "$branch" = "master" || die "Non-master branch: $branch"
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

	domain=$(grep "travis-ci\.[a-z]*/$repoSlug" pom.xml 2>/dev/null | sed 's/.*\(travis-ci\.[a-z]*\).*/\1/')
	test "$domain" &&
		info "Detected domain from pom.xml: $domain" ||
		die "No valid ciManagement section in pom.xml. Please add one, then try again."

	case $domain in
		travis-ci.com) mode=pro;;
		travis-ci.org) mode=org;;
		*) die "Unsupported domain: $domain";;
	esac

	# -- Travis sanity checks --

	test -e "$travisDir" -a ! -d "$travisDir" && die "$travisDir is not a directory"
	test -e "$travisConfig" -a ! -f "$travisConfig" && die "$travisConfig is not a regular file"
	test -e "$travisConfig" && warn "$travisConfig already exists"
	test -e "$travisBuildScript" && warn "$travisBuildScript already exists"

	# -- Do things --

	# Add/update the Travis configuration file.
	cat >"$tmpFile" <<EOL
language: java
jdk: openjdk8
branches:
  only:
  - master
  - "/.*-[0-9]+\\\\..*/"
install: true
script: "$travisBuildScript"
cache:
  directories:
  - "~/.m2/repository"
EOL
	update "$travisConfig"

	# Add/update the Travis build script.
	cat >"$tmpFile" <<EOL
#!/bin/sh
curl -fsLO https://raw.githubusercontent.com/scijava/scijava-scripts/master/travis-build.sh
sh travis-build.sh
EOL
	chmod +x "$tmpFile"
	update "$travisBuildScript"

	# Remove obsolete Travis-related files.
	if [ -f "$travisSettingsFile" ]
	then
		info "Removing obsolete $travisSettingsFile (travis-build.sh generates it now)"
		$EXEC git rm -f "$travisSettingsFile"
	fi
	if [ -f "$travisNotifyScript" ]
	then
		info "Removing obsolete $travisNotifyScript (ImageJ Jenkins is going away)"
		$EXEC git rm -f "$travisNotifyScript"
	fi
	$EXEC git diff-index --quiet HEAD -- || $EXEC git ci -m "Travis: remove obsolete files"

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
		test "$releaseProfile" = 'deploy-to-imagej' ||
			warn "Unknown release profile: $releaseProfile"
	else
		info 'Adding <releaseProfiles> property'
		cp pom.xml "$tmpFile"
		perl -0777 -i -pe 's/(\n\t<\/properties>\n)/\n\n\t\t<!-- NB: Deploy releases to the ImageJ Maven repository. -->\n\t\t<releaseProfiles>deploy-to-imagej<\/releaseProfiles>\1/igs' "$tmpFile"
		update pom.xml 'POM: deploy releases to the ImageJ repository'
	fi

	# update the README
	if grep -q "travis-ci\.[a-zA-Z0-9/_-]*\.svg" README.md >/dev/null 2>&1
	then
		info "Updating README.md Travis badge"
		sed "s|travis-ci\.[a-zA-Z0-9/_-]*|$domain/$repoSlug|g" README.md >"$tmpFile"
		update README.md 'Travis: fix README.md badge link'
	else
		info "Adding Travis badge to README.md"
		echo "[![](https://$domain/$repoSlug.svg?branch=master)](https://$domain/$repoSlug)" >"$tmpFile"
		echo >>"$tmpFile"
		test -f README.md && cat README.md >>"$tmpFile"
		update README.md 'Travis: add badge to README.md'
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
			$EXEC travis encrypt --$mode "$p" --add env.global --repo "$repoSlug"
			test $? -eq 0 || die "Failed to encrypt variable '$p'"
		done <"$varsFile"
		$EXEC git commit "$travisConfig" -m "Travis: add encrypted environment variables"
	else
		warn "No $varsFile found. Travis will not have any environment variables set!"
	fi

	# encrypt GPG keypair
	if [ -f "$signingKeySourceFile" ]
	then
		info "Encrypting $signingKeyDestFile"
		if [ -z "$EXEC" ]
		then
			rm -f "$signingKeyDestFile.enc"
			encryptOutput=$(travis encrypt-file --$mode "$signingKeySourceFile" "$signingKeyDestFile.enc" --repo "$repoSlug")
			test $? -eq 0 || die "Failed to encrypt signing key."
			encryptResult=$(echo "$encryptOutput" | grep openssl)
			test "$encryptResult" || die "No openssl variables emitted."
			key=$(echo "$encryptResult" | cut -d' ' -f4)
			iv=$(echo "$encryptResult" | cut -d' ' -f6)
			sed -i.bak "s/\(sh travis-build.sh\)/\1 $key $iv/" "$travisBuildScript"
			rm -f "$travisBuildScript.bak"
			git add "$travisBuildScript" "$signingKeyDestFile.enc"
			git commit -m "Travis: add encrypted GPG signing keypair"
		fi
	else
		warn "No $signingKeySourceFile found. Travis will not be able to do GPG signing!"
	fi
}

test -d "$credentialsDir" ||
	die "This script requires configuration stored in $credentialsDir,\n" \
		"including $varsFile for needed environment variables,\n" \
		"and $signingKeySourceFile for signing of artifacts.\n" \
		"Please contact a SciJava administrator to receive a copy of this content."

# check prerequisites
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
