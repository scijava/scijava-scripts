#!/bin/sh

#
# travis-build.sh - A script to build and/or release SciJava-based projects.
#

dir="$(dirname "$0")"

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
	echo "== Decrypting GPG keypair =="
	openssl aes-256-cbc -K "$key" -iv "$iv" -in "$keyFile.enc" -out "$keyFile" -d
fi
if [ "$TRAVIS_SECURE_ENV_VARS" = true \
	-a "$TRAVIS_PULL_REQUEST" = false \
	-a -f "$keyFile" ]
then
	echo "== Importing GPG keypair =="
	gpg --batch --fast-import "$keyFile"
fi

# Run the build.
if [ "$TRAVIS_SECURE_ENV_VARS" = true \
	-a "$TRAVIS_PULL_REQUEST" = false \
	-a "$TRAVIS_BRANCH" = master ]
then
	echo "== Building and deploying master SNAPSHOT =="
	mvn -B -Pdeploy-to-imagej deploy
elif [ "$TRAVIS_SECURE_ENV_VARS" = true \
	-a "$TRAVIS_PULL_REQUEST" = false \
	-a -f release.properties ]
then
	echo "== Cutting and deploying release version =="
	mvn -B release:perform
else
	echo "== Building the artifact locally only =="
	mvn -B install
fi
