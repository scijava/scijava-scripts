#!/bin/sh

#
# travis-javadoc.sh - A script to build the javadocs of a SciJava-based project.
#

if [ "$TRAVIS_SECURE_ENV_VARS" = true \
  -a "$TRAVIS_PULL_REQUEST" = false \
  -a "$TRAVIS_BRANCH" = master ]
then
  project=$1

  # Build the javadocs.
  mvn -Pbuild-javadoc &&
  test -d target/apidocs &&

  # Configure SSH. The file .travis/javadoc.scijava.org.enc must contain
  # an encrypted private RSA key for communicating with the git remote.
  mkdir -p "$HOME/.ssh" &&
  openssl aes-256-cbc -K "$encrypted_cb3727795fd5_key" -iv "$encrypted_cb3727795fd5_iv" -in '.travis/javadoc.scijava.org.enc' -out "$HOME/.ssh/id_rsa" -d &&
  echo 'github.com,192.30.252.130 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==' > "$HOME/.ssh/known_hosts" &&

  # Configure git settings.
  git config --global user.email "travis@travis-ci.org" &&
  git config --global user.name "Travis CI" &&

  # Clone the javadoc.scijava.org repository.
  git clone --quiet --depth 1 git@github.com:scijava/javadoc.scijava.org > /dev/null &&

  # Update the relevant javadocs.
  cd javadoc.scijava.org &&
  rm -rf "$project" &&
  mv ../target/apidocs "$project" &&

  # Commit and push the changes.
  git add "$project" &&
  git commit -m "Update $project javadocs (Travis build $TRAVIS_BUILD_NUMBER)" &&
  git push -q origin gh-pages > /dev/null

  echo "Update complete."
else
  echo "Skipping non-canonical branch $TRAVIS_BRANCH"
fi
