#!/bin/bash

#
# ci-setup-github-actions.sh - Set CI-related environment variables from GitHub Actions.
#

echo "BUILD_REPOSITORY=https://github.com/$GITHUB_REPOSITORY"
echo "BUILD_REPOSITORY=https://github.com/$GITHUB_REPOSITORY" >> $GITHUB_ENV

echo "BUILD_OS=$RUNNER_OS"
echo "BUILD_OS=$RUNNER_OS" >> $GITHUB_ENV

echo "BUILD_BASE_REF=$GITHUB_BASE_REF"
echo "BUILD_BASE_REF=$GITHUB_BASE_REF" >> $GITHUB_ENV

echo "BUILD_HEAD_REF=$GITHUB_HEAD_REF"
echo "BUILD_HEAD_REF=$GITHUB_HEAD_REF" >> $GITHUB_ENV
