#!/bin/sh

#
# travis-build.sh - A script to build and/or release SciJava-based projects.
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
if [ -f pom.xml ]
then
	echo travis_fold:start:travis-build.sh-maven
	echo "= Maven build ="
	echo
	echo "== Configuring Maven =="

	# NB: Suppress "Downloading/Downloaded" messages.
	# See: https://stackoverflow.com/a/35653426/1207769
	export MAVEN_OPTS=-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn

	# Populate the settings.xml configuration.
	mkdir -p "$HOME/.m2"
	settingsFile="$HOME/.m2/settings.xml"
	customSettings=.travis/settings.xml
	test -f "$customSettings" && cp "$customSettings" "$settingsFile" ||
	cat >"$settingsFile" <<EOL
<settings>
	<servers>
		<server>
			<id>imagej.releases</id>
			<username>travis</username>
			<password>\${env.MAVEN_PASS}</password>
		</server>
		<server>
			<id>imagej.snapshots</id>
			<username>travis</username>
			<password>\${env.MAVEN_PASS}</password>
		</server>
		<server>
			<id>sonatype-nexus-releases</id>
			<username>scijava-ci</username>
			<password>\${env.OSSRH_PASS}</password>
		</server>
	</servers>
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

	# Install GPG on OSX/macOS
	if [ "$TRAVIS_OS_NAME" = osx ]
	then
		brew install gnupg2
	fi

	# Import the GPG signing key.
	keyFile=.travis/signingkey.asc
	key=$1
	iv=$2
	if [ "$key" -a "$iv" -a -f "$keyFile.enc" ]
	then
		# NB: Key and iv values were given as arguments.
		echo
		echo "== Decrypting GPG keypair =="
		openssl aes-256-cbc -K "$key" -iv "$iv" -in "$keyFile.enc" -out "$keyFile" -d
		checkSuccess $?
	fi
	if [ "$TRAVIS_SECURE_ENV_VARS" = true \
		-a "$TRAVIS_PULL_REQUEST" = false \
		-a -f "$keyFile" ]
	then
		echo
		echo "== Importing GPG keypair =="
		gpg --batch --fast-import "$keyFile"
		checkSuccess $?
	fi

	# Run the build.
	if [ "$TRAVIS_SECURE_ENV_VARS" = true \
		-a "$TRAVIS_PULL_REQUEST" = false \
		-a "$TRAVIS_BRANCH" = master ]
	then
		echo
		echo "== Building and deploying master SNAPSHOT =="
		mvn -B -Pdeploy-to-imagej deploy
		checkSuccess $?
	elif [ "$TRAVIS_SECURE_ENV_VARS" = true \
		-a "$TRAVIS_PULL_REQUEST" = false \
		-a -f release.properties ]
	then
		echo
		echo "== Cutting and deploying release version =="
		mvn -B release:perform
		checkSuccess $?
	else
		echo
		echo "== Building the artifact locally only =="
		mvn -B install javadoc:javadoc
		checkSuccess $?
	fi
	echo travis_fold:end:travis-build.sh-maven
fi

# Execute Jupyter notebooks.
if which jupyter >/dev/null 2>/dev/null
then
	echo travis_fold:start:travis-build.sh-jupyter
	echo "= Jupyter notebooks ="
	# NB: This part is fiddly. We want to loop over files even with spaces,
	# so we use the "find ... -print0 | while read $'\0' ..." idiom.
	# However, that runs the piped expression in a subshell, which means
	# that any updates to the success variable will not persist outside
	# the loop. So we suppress all stdout inside the loop, echoing only
	# the final value of success upon completion, and then capture the
	# echoed value back into the parent shell's success variable.
	success=$(find . -name '*.ipynb' -print0 | {
		while read -d $'\0' nbf
		do
			echo 1>&2
			echo "== $nbf ==" 1>&2
			jupyter nbconvert --execute --stdout "$nbf" >/dev/null
			checkSuccess $?
		done
		echo $success
	})
	echo travis_fold:end:travis-build.sh-jupyter
fi

exit $success
