#!/usr/bin/env bash
# shellcheck disable=SC2129

set -e

# Echo all environment variables used by this script
echo "----------- get_repo -----------"
echo "Environment variables:"
echo "CI_BUILD=${CI_BUILD}"
echo "GITHUB_REPOSITORY=${GITHUB_REPOSITORY}"
echo "RELEASE_VERSION=${RELEASE_VERSION}"
echo "VSCODE_LATEST=${VSCODE_LATEST}"
echo "VSCODE_QUALITY=${VSCODE_QUALITY}"
echo "GITHUB_ENV=${GITHUB_ENV}"

echo "SHOULD_DEPLOY=${SHOULD_DEPLOY}"
echo "SHOULD_BUILD=${SHOULD_BUILD}"
echo "-------------------------"

# git workaround
if [[ "${CI_BUILD}" != "no" ]]; then
  git config --global --add safe.directory "/__w/$( echo "${GITHUB_REPOSITORY}" | awk '{print tolower($0)}' )"
fi

VOID_BRANCH="main"
echo "Cloning void ${VOID_BRANCH}..."

mkdir -p vscode
cd vscode || { echo "'vscode' dir not found"; exit 1; }

git init -q
# Point the builder at your fork of the editor instead of the official Void repo.
# This makes the builder clone and build your "Void VDM Edition" source.
git remote add origin https://github.com/justinlietz93/void_vdm-edition.git

# Allow callers to specify a particular commit to checkout via the
# environment variable VOID_COMMIT.  We still default to the tip of the
# ${VOID_BRANCH} branch when the variable is not provided.  Keeping
# VOID_BRANCH as "main" ensures the rest of the script (and downstream
# consumers) behave exactly as before.
if [[ -n "${VOID_COMMIT}" ]]; then
  echo "Using explicit commit ${VOID_COMMIT}"
  # Fetch just that commit to keep the clone shallow.
  git fetch --depth 1 origin "${VOID_COMMIT}"
  git checkout "${VOID_COMMIT}"
else
  git fetch --depth 1 origin "${VOID_BRANCH}"
  git checkout FETCH_HEAD
fi

MS_TAG=$( node -e "console.log(require('./package.json').version)" )
MS_COMMIT=$VOID_BRANCH # Void - MS_COMMIT doesn't seem to do much
VOID_VERSION=$( node -e "console.log(require('./product.json').voidVersion)" ) # Void added this

if [[ -n "${VOID_RELEASE}" ]]; then # Void added VOID_RELEASE as optional to bump manually
  RELEASE_VERSION="${MS_TAG}${VOID_RELEASE}"
else
  VOID_RELEASE=$( node -e "console.log(require('./product.json').voidRelease)" )
  RELEASE_VERSION="${MS_TAG}${VOID_RELEASE}"
fi
# Void - RELEASE_VERSION is later used as version (1.0.3+RELEASE_VERSION), so it MUST be a number or it will throw a semver error in void


echo "RELEASE_VERSION=\"${RELEASE_VERSION}\""
echo "MS_COMMIT=\"${MS_COMMIT}\""
echo "MS_TAG=\"${MS_TAG}\""

cd ..

# for GH actions
if [[ "${GITHUB_ENV}" ]]; then
  echo "MS_TAG=${MS_TAG}" >> "${GITHUB_ENV}"
  echo "MS_COMMIT=${MS_COMMIT}" >> "${GITHUB_ENV}"
  echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"
  echo "VOID_VERSION=${VOID_VERSION}" >> "${GITHUB_ENV}" # Void added this
fi



echo "----------- get_repo exports -----------"
echo "MS_TAG ${MS_TAG}"
echo "MS_COMMIT ${MS_COMMIT}"
echo "RELEASE_VERSION ${RELEASE_VERSION}"
echo "VOID VERSION ${VOID_VERSION}"
echo "----------------------"


export MS_TAG
export MS_COMMIT
export RELEASE_VERSION
export VOID_VERSION
