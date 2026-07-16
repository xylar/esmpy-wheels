#!/usr/bin/env bash
#
# Fetch the ESMF source into ./esmf (shallow clone at the pinned ref) if not
# already present. The ref is read from versions.env (ESMF_REPO_URL, ESMF_REF).
#
# The wheel's esmpy is built from this source, so the ref must contain the
# wheel-aware loader change. A shallow clone still carries the git metadata and
# source header that setuptools-git-versioning uses to derive the version.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO_ROOT/versions.env"

DEST="$REPO_ROOT/esmf"
if [ -e "$DEST/makefile" ]; then
  echo "ESMF source already present at $DEST"
  exit 0
fi

echo "==> Cloning $ESMF_REPO_URL @ $ESMF_REF -> $DEST"
git clone --depth 1 --branch "$ESMF_REF" "$ESMF_REPO_URL" "$DEST"
