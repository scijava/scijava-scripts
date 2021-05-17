#!/bin/bash

#
# github-action-build.sh - A script to build and/or release SciJava-based projects
#                          automatically using GitHub Actions.
#

dir="$(dirname "$0")"

success=0
checkSuccess() {
	# Log non-zero exit code.
	test $1 -eq 0 || echo "==> FAILED: EXIT CODE $1" 1>&2

	# Record the first non-zero exit code.
	test $success -eq 0 && success=$1
}

# Build Maven projects.
if [ -f pom.xml ]; then
	echo ::group::"= Maven build ="
	echo
	echo "== Configuring Maven =="

	# NB: Suppress "Downloading/Downloaded" messages.
	# See: https://stackoverflow.com/a/35653426/1207769
	export MAVEN_OPTS="$MAVEN_OPTS -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn"

	# Populate the settings.xml configuration.
	mkdir -p "$HOME/.m2"
	settingsFile="$HOME/.m2/settings.xml"
	customSettings=.gh-action/settings.xml
	if [ -f "$customSettings" ]; then
		cp "$customSettings" "$settingsFile"
	else
		cat >"$settingsFile" <<EOL
<settings>
	<servers>
		<server>
			<id>scijava.releases</id>
			<username>scijava-ci</username>
			<password>\${env.MAVEN_PASS}</password>
		</server>
		<server>
			<id>scijava.snapshots</id>
			<username>scijava-ci</username>
			<password>\${env.MAVEN_PASS}</password>
		</server>
		<server>
			<id>sonatype-nexus-releases</id>
			<username>scijava-ci</username>
			<password>\${env.OSSRH_PASS}</password>
		</server>
	</servers>
EOL
# 		# NB: Use maven.scijava.org instead of Central if defined in repositories.
# 		# This hopefully avoids intermittent "ReasonPhrase:Forbidden" errors
# 		# when the Travis build pings Maven Central; see travis-ci/travis-ci#6593.
# 		grep -A 2 '<repository>' pom.xml | grep -q 'maven.scijava.org' &&
# 			cat >>"$settingsFile" <<EOL
# 	<mirrors>
# 		<mirror>
# 			<id>scijava-mirror</id>
# 			<name>SciJava mirror</name>
# 			<url>https://maven.scijava.org/content/groups/public/</url>
# 			<mirrorOf>central</mirrorOf>
# 		</mirror>
# 	</mirrors>
# EOL
		cat >>"$settingsFile" <<EOL
	<profiles>
		<profile>
			<id>gpg</id>
			<activation>
				<file>
					<exists>\${env.HOME}/.gnupg</exists>
				</file>
			</activation>
			<properties>
				<gpg.keyname>\${env.GPG_KEY_NAME}</gpg.keyname>
				<gpg.passphrase>\${env.GPG_PASSPHRASE}</gpg.passphrase>
			</properties>
		</profile>
	</profiles>
</settings>
EOL
	fi

	# Determine whether deploying will be possible.
	deployOK=
	ciURL=$(mvn -q -Denforcer.skip=true -Dexec.executable=echo -Dexec.args='${project.ciManagement.url}' --non-recursive validate exec:exec 2>&1)
	if [ $? -ne 0 ]; then
		echo "No deploy -- could not extract ciManagement URL"
		echo "Output of failed attempt follows:"
		echo "$ciURL"
	else
		# https://developer.okta.com/blog/2020/05/18/travis-ci-to-github-actions
		# This website specifies Travis environment variables with their
		# equivalent GitHub Actions environment variables
		ciRepo=${ciURL##*/}
		ciPrefix=${ciURL%/*}
		ciOrg=${ciPrefix##*/}
		# https://docs.github.com/en/actions/reference/encrypted-secrets
		if [ "${secure_env}" != true ]; then
			echo "No deploy -- secure environment variables not available"
			echo ${secure_env}
			echo ${pull_request}
			echo ${repo_fork}
			echo ${runner_os}
			echo ${git_branch}
			echo ${python_version}
			echo ${ciRepo}
			echo ${ciPrefix}
			echo ${ciOrg}
		fi
		if [ "${pull_request}" != false ]; then
			echo "No deploy -- pull request detected"
		fi
		if [ "${repo_fork}" != "$ciOrg/$ciRepo" ]; then
			echo "No deploy -- repository fork: ${repo_fork}} != $ciOrg/$ciRepo"
		else
			echo "All checks passed for artifact deployment"
			deployOK=1
		fi
	fi

	# Install GPG on OSX/macOS
	if [ "${runner_os}" = 'macOS' ]; then
		HOMEBREW_NO_AUTO_UPDATE=1 brew install gnupg2
	fi

	# Import the GPG signing key.
	keyFile=.gh-action/signingkey.asc
	key=$1
	iv=$2
	if [ "$key" -a "$iv" -a -f "$keyFile.enc" ]; then
		# NB: Key and iv values were given as arguments.
		echo
		echo "== Decrypting GPG keypair =="
		openssl aes-256-cbc -K "$key" -iv "$iv" -in "$keyFile.enc" -out "$keyFile" -d
		checkSuccess $?
	fi
	if [ "$deployOK" -a -f "$keyFile" ]; then
		echo
		echo "== Importing GPG keypair =="
		gpg --batch --fast-import "$keyFile"
		checkSuccess $?
	fi

	# Run the build.
	BUILD_ARGS='-B -Djdk.tls.client.protocols="TLSv1,TLSv1.1,TLSv1.2"'
	if [ "$deployOK" -a "${git_branch}" = master ]; then
		echo
		echo "== Building and deploying master SNAPSHOT =="
		mvn -Pdeploy-to-scijava $BUILD_ARGS deploy
		checkSuccess $?
	elif [ "$deployOK" -a -f release.properties ]; then
		echo
		echo "== Cutting and deploying release version =="
		mvn -B $BUILD_ARGS release:perform
		checkSuccess $?
		echo "== Invalidating SciJava Maven repository cache =="
		curl -fsLO https://raw.githubusercontent.com/scijava/scijava-scripts/master/maven-helper.sh &&
			gav=$(sh maven-helper.sh gav-from-pom pom.xml) &&
			ga=${gav%:*} &&
			echo "--> Artifact to invalidate = $ga" &&
			echo "machine maven.scijava.org" >"$HOME/.netrc" &&
			echo "        login scijava-ci" >>"$HOME/.netrc" &&
			echo "        password $MAVEN_PASS" >>"$HOME/.netrc" &&
			sh maven-helper.sh invalidate-cache "$ga"
		checkSuccess $?
	else
		echo
		echo "== Building the artifact locally only =="
		mvn $BUILD_ARGS install javadoc:javadoc
		checkSuccess $?
	fi
	echo ::endgroup::
fi

# Configure conda environment, if one is needed.
if [ -f environment.yml ]; then
	echo ::group::"= Conda setup ="

	condaDir=$HOME/miniconda
	condaSh=$condaDir/etc/profile.d/conda.sh
	if [ ! -f "$condaSh" ]; then
		echo
		echo "== Installing conda =="
		if [ "${python_version}" = "2.7" ]; then
			wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh -O miniconda.sh
		else
			wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
		fi
		rm -rf "$condaDir"
		bash miniconda.sh -b -p "$condaDir"
		checkSuccess $?
	fi

	echo
	echo "== Updating conda =="
	. "$condaSh" &&
		conda config --set always_yes yes --set changeps1 no &&
		conda update -q conda &&
		conda info -a
	checkSuccess $?

	echo
	echo "== Configuring environment =="
	condaEnv=github-scijava
	test -d "$condaDir/envs/$condaEnv" && condaAction=update || condaAction=create
	conda env "$condaAction" -n "$condaEnv" -f environment.yml &&
		conda activate "$condaEnv"
	checkSuccess $?

	echo ::endgroup::
fi

# Execute Jupyter notebooks.
if which jupyter >/dev/null 2>/dev/null; then
	echo ::group::"= Jupyter notebooks ="
	# NB: This part is fiddly. We want to loop over files even with spaces,
	# so we use the "find ... -print0 | while read $'\0' ..." idiom.
	# However, that runs the piped expression in a subshell, which means
	# that any updates to the success variable will not persist outside
	# the loop. So we suppress all stdout inside the loop, echoing only
	# the final value of success upon completion, and then capture the
	# echoed value back into the parent shell's success variable.
	success=$(find . -name '*.ipynb' -print0 | {
		while read -d $'\0' nbf; do
			echo 1>&2
			echo "== $nbf ==" 1>&2
			jupyter nbconvert --execute --stdout "$nbf" >/dev/null
			checkSuccess $?
		done
		echo $success
	})
	echo ::endgroup::
fi

exit $success
