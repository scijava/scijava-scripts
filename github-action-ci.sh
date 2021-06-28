#!/bin/bash

#
# github-action-ci.sh - A script to set up ci-related environment variables from GitHub Actions
#

echo "BUILD_REPOSITORY=${GITHUB_REPOSITORY}"
echo "BUILD_OS=${RUNNER_OS}" 

echo "BUILD_REPOSITORY=${GITHUB_REPOSITORY}" >> $GITHUB_ENV
echo "BUILD_OS=${RUNNER_OS}" >> $GITHUB_ENV
