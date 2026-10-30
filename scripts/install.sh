#!/bin/bash
# Installs Droptimize, or updates it to the latest preview build. On a Mac, in Terminal:
#
#   curl -fsSL https://github.com/bimanshu/Droptimize/releases/download/preview/install.sh | bash
#
# Downloads the app, quits the running copy, replaces it in Applications and opens the new one.
# Files downloaded with curl aren't quarantined, so there's no Gatekeeper step.
# Published alongside every preview build by .github/workflows/build.yml (which also tests it).
#
# For testing: DROPTIMIZE_ZIP (a URL or file:// path), DROPTIMIZE_DIR (install folder),
# DROPTIMIZE_NO_OPEN=1 (don't open it afterwards).
set -euo pipefail

# Everything is in main() so bash has read the whole script before running any of it
# (it arrives through a pipe).
main() {
  local app_name="Droptimize"
  local bundle_id="com.droptimize.app"
  local zip_url="${DROPTIMIZE_ZIP:-https://github.com/bimanshu/Droptimize/releases/download/preview/Droptimize.zip}"

  [ "$(uname -s)" = Darwin ] || fail "this installs a Mac app; run it on a Mac."
  local version major
  version="$(sw_vers -productVersion)"
  major="${version%%.*}"
  [ "$major" -ge 14 ] || fail "Droptimize needs macOS 14 (Sonoma) or newer. This Mac has $version."

  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT

  say "Downloading the latest Droptimize…"
  # Retries cover the few seconds while a new build is being swapped in.
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "$zip_url" -o "$work/app.zip" \
    || fail "couldn't download it. Check your internet connection and try again in a minute."
  ditto -x -k "$work/app.zip" "$work/unzipped"
  local new="$work/unzipped/$app_name.app"
  [ -d "$new" ] || fail "the download didn't contain the app."
  codesign --verify --deep --strict "$new" 2>/dev/null \
    || fail "the downloaded app failed its signature check, so it wasn't installed."

  local dir
  if [ -n "${DROPTIMIZE_DIR:-}" ]; then
    dir="$DROPTIMIZE_DIR"
  elif [ -w /Applications ]; then
    dir=/Applications
  else
    dir="$HOME/Applications"
  fi
  mkdir -p "$dir"
  local target="$dir/$app_name.app"

  if pgrep -x "$app_name" >/dev/null; then
    say "Quitting the running copy…"
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    local tries=0
    while pgrep -x "$app_name" >/dev/null && [ "$tries" -lt 10 ]; do
      sleep 0.5
      tries=$((tries + 1))
    done
    pkill -x "$app_name" 2>/dev/null || true
  fi

  # Copy in beside the old one first, so a failure never leaves you with no app.
  rm -rf "$target.new"
  ditto "$new" "$target.new"
  rm -rf "$target"
  mv "$target.new" "$target"
  xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

  local build
  build="$(defaults read "$target/Contents/Info" CFBundleVersion 2>/dev/null || echo "?")"
  if [ -n "${DROPTIMIZE_NO_OPEN:-}" ]; then
    say "Installed Droptimize (build $build) in $dir."
  else
    say "Installed Droptimize (build $build) in $dir. Opening it…"
    open "$target"
  fi
}

say() { printf '%s\n' "$*"; }
fail() { printf 'Droptimize: %s\n' "$*" >&2; exit 1; }

main "$@"
