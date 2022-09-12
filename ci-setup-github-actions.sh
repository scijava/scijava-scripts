#!/bin/bash

#
# ci-setup-github-actions.sh - Set CI-related environment variables from GitHub Actions.
#

echo "BUILD_REPOSITORY=https://github.com/${GITHUB_REPOSITORY}"
echo "BUILD_OS=${RUNNER_OS}"
echo "BUILD_DEPLOY_FORBIDDEN=..." # CTR START HERE - use GITHUB-specific env vars set upon PR to decide this

echo "BUILD_REPOSITORY=https://github.com/${GITHUB_REPOSITORY}" >> $GITHUB_ENV
echo "BUILD_OS=${RUNNER_OS}" >> $GITHUB_ENV
