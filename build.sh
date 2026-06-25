#!/usr/bin/env bash
#
# Build a custom, immutable production image containing:
#   frappe (version-16)  +  helpdesk (main)  +  telephony (develop)
#
# Apps baked at build time = no `bench get-app` at runtime, assets pre-built.
# Re-run this script (then redeploy + migrate) to update.
#
# Run this ON THE SERVER, from inside a clone of frappe_docker, with apps.json
# present in the build context. See README.md "Build" section.
#
set -euo pipefail

# ---- config ---------------------------------------------------------------
FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
IMAGE_NAME="${IMAGE_NAME:-helpdesk}"
IMAGE_TAG="${IMAGE_TAG:-v16}"
APPS_JSON="${APPS_JSON:-apps.json}"        # path to the apps.json in this repo
# If pushing to a registry, set e.g. IMAGE_NAME=ghcr.io/youruser/helpdesk
# ---------------------------------------------------------------------------

if [ ! -f images/layered/Containerfile ]; then
  echo "ERROR: run this from the root of a frappe_docker clone." >&2
  echo "       git clone https://github.com/frappe/frappe_docker && cd frappe_docker" >&2
  exit 1
fi

echo ">> Building ${IMAGE_NAME}:${IMAGE_TAG} (frappe ${FRAPPE_BRANCH} + helpdesk + telephony)"

# apps.json is passed as a BuildKit *secret* so any private tokens never land
# in image-history metadata. (Helpdesk/telephony are public, but this is the
# documented best practice.)
DOCKER_BUILDKIT=1 docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH="${FRAPPE_BRANCH}" \
  --secret=id=apps_json,src="${APPS_JSON}" \
  --tag="${IMAGE_NAME}:${IMAGE_TAG}" \
  --file=images/layered/Containerfile .

echo ">> Done: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "   If the toolchain mismatches version-16, override e.g.:"
echo "     --build-arg=PYTHON_VERSION=3.11.9 --build-arg=NODE_VERSION=20.19.2"
