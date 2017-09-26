#!/bin/sh

#
# travis-build.sh - A script to build and/or release SciJava-based projects.
#

# NB: Suppress "Downloading/Downloaded" messages.
# See: https://stackoverflow.com/a/35653426/1207769
export MAVEN_OPTS=-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn

dir="$(dirname "$0")"
if [ "$TRAVIS_SECURE_ENV_VARS" = true \
  -a "$TRAVIS_PULL_REQUEST" = false \
  -a "$TRAVIS_BRANCH" = master ]
then
  echo "== Building and deploying master SNAPSHOT =="
  mvn -B -Pdeploy-to-imagej deploy --settings "$dir/.travis/settings.xml"
elif [ "$TRAVIS_SECURE_ENV_VARS" = true \
  -a "$TRAVIS_PULL_REQUEST" = false \
  -a -f release.properties ]
then
  echo "== Cutting and deploying release version =="
  mvn -B --settings "$dir/.travis/settings.xml" release:perform
else
  echo "== Building the artifact locally only =="
  mvn -B install
fi
