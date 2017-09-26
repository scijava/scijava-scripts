#!/bin/sh

#
# travis-build.sh - A script to build and/or release SciJava-based projects.
#

dir="$(dirname "$0")"
if [ "$TRAVIS_SECURE_ENV_VARS" = true \
  -a "$TRAVIS_PULL_REQUEST" = false \
  -a "$TRAVIS_BRANCH" = master ]
then
  echo "== Building and deploying master SNAPSHOT =="
  mvn -Pdeploy-to-imagej deploy --settings "$dir/.travis/settings.xml"
elif [ "$TRAVIS_SECURE_ENV_VARS" = true \
  -a "$TRAVIS_PULL_REQUEST" = false \
  -a -f release.properties ]
then
  echo "== Cutting and deploying release version =="
  mvn release:perform
else
  echo "== Building the artifact locally only =="
  mvn install
fi
