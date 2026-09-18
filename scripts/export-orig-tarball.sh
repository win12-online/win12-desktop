#!/usr/bin/env bash
#
# export-orig-tarball.sh
#
# Build the Debian upstream orig tarball for win12-desktop, expanding every
# (possibly nested) Git submodule from the commit pinned by the superproject.
#
# Why this script exists:
#   `git archive HEAD` only archives the repository it is run in. Submodules
#   (tauri/src, and the nested tauri/src/lang) are emitted as *empty*
#   directories, which previously produced an orig tarball that was missing
#   the web front-end and the locale data. Copying the working tree was also
#   fragile: it could drag in `debian/`, `.git` link files and build artifacts,
#   which made dpkg-source fail with:
#       dpkg-source: error: unrepresentable changes to source
#       dpkg-source: error: aborting due to unexpected upstream changes
#
# This script archives the top-level repository and, recursively, every direct
# child submodule, layering each archive on top of the previous one. Only
# tracked content at the pinned commit is exported, so the result is a pristine
# upstream tree: no `debian/` directory, no `.git` metadata and no build
# products. File modes come from the Git index (PNG/WAV/... are 0644), which
# also avoids the executable-bit warnings seen with plain `tar` copies.
#
# Usage:
#   scripts/export-orig-tarball.sh UPSTREAM_VERSION [OUTPUT_DIR]
#
# Example:
#   scripts/export-orig-tarball.sh 0.3.0 /tmp/ppa-build
#
# Output:
#   <OUTPUT_DIR>/win12-desktop_<UPSTREAM_VERSION>.orig.tar.gz
#   (OUTPUT_DIR defaults to the parent of the repository working tree, which
#   is where debuild/dpkg-source expect the orig tarball.)
#
# The script exits non-zero if the submodules cannot be initialised, if the
# version is invalid, or if the resulting tarball fails any content check.

set -euo pipefail

PKG="win12-desktop"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

UPSTREAM_VERSION="${1:-}"
OUTPUT_DIR="${2:-$(cd "$ROOT_DIR/.." && pwd)}"

if [[ -z "$UPSTREAM_VERSION" ]]; then
  echo "usage: $0 UPSTREAM_VERSION [OUTPUT_DIR]" >&2
  exit 2
fi

# Debian upstream-version grammar used by this project: strict X.Y.Z
# (the leading "v" must already have been stripped by the caller).
if [[ ! "$UPSTREAM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: upstream version must look like 0.3.0, got '$UPSTREAM_VERSION'" >&2
  exit 2
fi

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: $ROOT_DIR is not a Git working tree" >&2
  exit 1
fi

# Make sure every nested submodule is checked out at the pinned commit. This
# is a no-op on a fresh `actions/checkout` with submodules: recursive, but it
# makes the script self-contained for local runs and for non-GitHub clones.
echo "==> Synchronising and initialising submodules recursively"
git -C "$ROOT_DIR" submodule sync --recursive
git -C "$ROOT_DIR" submodule update --init --recursive

echo "==> Recursive submodule status:"
git -C "$ROOT_DIR" submodule status --recursive | sed 's/^/    /'

TARBALL_NAME="${PKG}_${UPSTREAM_VERSION}.orig.tar.gz"
TOP_DIR="${PKG}-${UPSTREAM_VERSION}"

STAGE="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

DEST="$STAGE/$TOP_DIR"
mkdir -p "$DEST"

# export_tree REPO_DIR DEST_DIR
#
# Archive the tracked tree of REPO_DIR at its current HEAD into DEST_DIR, then
# do the same for each direct child submodule. Because every repository only
# lists its *direct* children via `git submodule status`, walking the tree
# recursively handles arbitrary nesting depth (tauri/src -> lang).
export_tree() {
  local repo="$1"
  local dest="$2"
  local sub_path

  mkdir -p "$dest"
  git -C "$repo" archive --format=tar HEAD | tar -x -C "$dest"

  while IFS= read -r sub_path; do
    [[ -n "$sub_path" ]] || continue
    if [[ ! -d "$repo/$sub_path" ]]; then
      echo "error: submodule directory '$sub_path' is missing in $repo" >&2
      echo "       (did 'git submodule update --init --recursive' succeed?)" >&2
      exit 1
    fi
    export_tree "$repo/$sub_path" "$dest/$sub_path"
  done < <(git -C "$repo" submodule status 2>/dev/null | awk '{print $2}')
}

echo "==> Exporting tracked tree (with nested submodules expanded)"
export_tree "$ROOT_DIR" "$DEST"

# Debian packaging lives only in the .debian.tar.xz, never in the orig tarball.
echo "==> Removing debian/ packaging directory from upstream tree"
rm -rf "$DEST/debian"

# ----------------------------------------------------------------------------
# Cargo vendoring for Launchpad/PPA offline builds.
#
# Launchpad buildds have no network, so `cargo build` cannot reach
# https://index.crates.io. We therefore snapshot the full dependency graph
# (as described by tauri/src-tauri/Cargo.lock) into the upstream tree. The
# vendor directory goes into the .orig.tar.* (NOT into .debian.tar.xz and NOT
# into Git) so that Launchpad receives it together with the rest of the
# source package.
#
# `cargo vendor` is run against the *working tree* of the locked crate so the
# result exactly matches Cargo.lock, then the produced tree is copied into the
# staging directory. Cargo never writes into $DEST during this step.
# ----------------------------------------------------------------------------
TAURI_CRATE="$ROOT_DIR/tauri/src-tauri"
VENDOR_DEST="$DEST/tauri/src-tauri/vendor"
VENDOR_TMP="$STAGE/vendor"

if [[ ! -f "$TAURI_CRATE/Cargo.lock" ]]; then
  echo "error: $TAURI_CRATE/Cargo.lock not found; cannot vendor without a lock file" >&2
  exit 1
fi

echo "==> Vendoring Rust dependencies (the only step that may use the network)"
# cargo vendor prints a sample source-replacement config on stdout; we do
# not need it (debian/rules generates the real, relocatable config at build
# time), so discard stdout rather than leaving an unused file behind.
if ! cargo vendor --locked --versioned-dirs \
  --manifest-path "$TAURI_CRATE/Cargo.toml" \
  "$VENDOR_TMP" > /dev/null 2>"$STAGE/vendor.err"; then
  echo "error: cargo vendor failed" >&2
  cat "$STAGE/vendor.err" >&2
  exit 1
fi
mv "$VENDOR_TMP" "$VENDOR_DEST"

VENDOR_CRATE_COUNT="$(find "$VENDOR_DEST" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
echo "    vendored crates: $VENDOR_CRATE_COUNT"
echo "    vendor size:    $(du -sh "$VENDOR_DEST" | awk '{print $1}')"
if [[ "$VENDOR_CRATE_COUNT" -eq 0 ]]; then
  echo "error: vendor directory is empty" >&2
  exit 1
fi

# Every vendored crate must carry its checksum manifest; a missing one would
# make `cargo build --offline` fail on Launchpad.
if crate="$(find "$VENDOR_DEST" -mindepth 1 -maxdepth 1 -type d \
             ! -name '.*' ! -exec test -f '{}/.cargo-checksum.json' \; -print -quit)" \
   && [[ -n "$crate" ]]; then
  echo "error: vendored crate missing .cargo-checksum.json: $crate" >&2
  exit 1
fi

# Defence in depth: a Git archive never contains these, but verify it so a
# future refactor cannot silently reintroduce the bug.
echo "==> Checking for leaked Git metadata"
if find "$DEST" \( -name '.git' -o -name '.gitmodules.local' \) -print -quit | grep -q .; then
  find "$DEST" -name '.git' -print
  echo "error: Git metadata leaked into the upstream tree" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
TARBALL_PATH="$OUTPUT_DIR/$TARBALL_NAME"

echo "==> Creating $TARBALL_PATH"
tar \
  --sort=name \
  --owner=0 --group=0 --numeric-owner \
  --format=gnu \
  -C "$STAGE" \
  -czf "$TARBALL_PATH" \
  "$TOP_DIR"

echo "==> Verifying tarball"

# List the tarball exactly once. Piping into `grep -q` makes grep close the
# pipe as soon as it matches, which SIGPIPEs tar and (under pipefail) reports
# a spurious failure, so all checks below grep this captured listing instead.
LISTING="$STAGE/tarball.listing"
tar -tzf "$TARBALL_PATH" > "$LISTING"

# Every entry must live under the single expected top-level directory.
if grep -vE "^${TOP_DIR//./\\.}/" "$LISTING" | grep -q .; then
  echo "error: tarball contains entries outside '$TOP_DIR/'" >&2
  grep -vE "^${TOP_DIR//./\\.}/" "$LISTING" | head
  exit 1
fi

# No Debian directory and no literal .git path ('.github' is allowed).
if grep -E "^${TOP_DIR//./\\.}/debian(/|$)" "$LISTING" | grep -q .; then
  echo "error: tarball must not contain debian/" >&2
  exit 1
fi
if grep -E "(^|/)\\.git($|/)" "$LISTING" | grep -q .; then
  echo "error: tarball must not contain any .git metadata" >&2
  exit 1
fi

# Build-time generated Cargo state must never be in the upstream tarball;
# vendor/ itself is expected, but .cargo (generated config) and .cargo-home
# (the CARGO_HOME cache) are not.
if grep -E "^${TOP_DIR//./\\.}/tauri/src-tauri/\\.cargo(/|$)" "$LISTING" | grep -q .; then
  echo "error: tarball must not contain tauri/src-tauri/.cargo (generated at build time)" >&2
  exit 1
fi
if grep -E "^${TOP_DIR//./\\.}/tauri/src-tauri/\\.cargo-home(/|$)" "$LISTING" | grep -q .; then
  echo "error: tarball must not contain tauri/src-tauri/.cargo-home" >&2
  exit 1
fi

# These files were missing from earlier broken tarballs and are the canaries
# for the two nested submodules (win12 front-end and win12-locales).
REQUIRED=(
  "tauri/src/apps/icons/explorer/disk.png"
  "tauri/src/icon/bilibili.png"
  "tauri/src/media/Windows Background.wav"
  "tauri/src/lang/README.md"
  "tauri/src/lang/lang/lang_en.properties"
)
for rel in "${REQUIRED[@]}"; do
  if ! grep -Fxq "$TOP_DIR/$rel" "$LISTING"; then
    echo "error: required file missing from tarball: $TOP_DIR/$rel" >&2
    exit 1
  fi
done

echo
echo "==> Tarball OK"
echo "    path: $TARBALL_PATH"
echo "    size: $(du -h "$TARBALL_PATH" | awk '{print $1}')"
echo "    sha256: $(sha256sum "$TARBALL_PATH" | awk '{print $1}')"
