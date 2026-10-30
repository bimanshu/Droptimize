#!/usr/bin/env bash
# Builds pinned native dependencies into Vendor/ (CORE.md §8). Vendor/ is generated, not committed.
#
#   macOS: universal (arm64 + x86_64) static libraries for the app. Runs automatically from
#          `xcodegen generate` (project.yml preGenCommand) and in CI.
#   Linux: a host-only build, so scripts/check-linux.sh can test the encoders without a Mac.
#
# Does nothing when the pinned version is already built. Needs curl and a C compiler (Xcode's on macOS).
set -euo pipefail
cd "$(dirname "$0")/.."

# libwebp: WebP encoding. BSD-3-Clause (fine in a paid, closed-source app). Approved by the owner 2026-10-30.
WEBP_VERSION=1.6.0
WEBP_SHA256=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
WEBP_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${WEBP_VERSION}.tar.gz"
MIN_MACOS=14.0

out=Vendor/libwebp
platform="$(uname -s)"
stamp="$WEBP_VERSION-$platform"
if [[ -f "$out/.built" && "$(cat "$out/.built")" == "$stamp" && -f "$out/lib/libwebp.a" ]]; then
  exit 0
fi
echo "Building libwebp $WEBP_VERSION ($platform)…"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL "$WEBP_URL" -o "$work/libwebp.tar.gz"
if command -v shasum >/dev/null; then sum=(shasum -a 256); else sum=(sha256sum); fi
echo "$WEBP_SHA256  $work/libwebp.tar.gz" | "${sum[@]}" -c - >/dev/null
tar xzf "$work/libwebp.tar.gz" -C "$work"
src="$work/libwebp-$WEBP_VERSION"

# The encoder, the decoder (used by tests), and their shared code. No mux/demux: no animation yet.
sources=("$src"/src/{dec,enc,dsp,utils}/*.c "$src"/sharpyuv/*.c)
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

# compile <objdir> <compiler and flags…>: compiles every source in parallel into objdir.
# (Written for the bash 3.2 that ships with macOS: no `wait -n`.)
compile() {
  local objdir=$1; shift
  mkdir -p "$objdir"
  printf '#!/bin/sh\nexec %s -c "$1" -o "$2"\n' "$(printf '%q ' "$@")" > "$objdir/cc.sh"
  chmod +x "$objdir/cc.sh"
  for f in "${sources[@]}"; do
    rel="${f#"$src"/}"
    printf '%s\0%s\0' "$f" "$objdir/${rel//\//_}.o"
  done | xargs -0 -n 2 -P "$jobs" "$objdir/cc.sh"
}

common=(-O2 -DNDEBUG -DWEBP_USE_THREAD -I "$src" -w)
rm -rf "$out"
mkdir -p "$out/lib" "$out/include/webp"

if [[ "$platform" == Darwin ]]; then
  slices=()
  for arch in arm64 x86_64; do
    flags=(xcrun clang -arch "$arch" -mmacosx-version-min="$MIN_MACOS" "${common[@]}")
    # Every Intel Mac that runs macOS 14 has SSE4.1, so use it everywhere.
    [[ "$arch" == x86_64 ]] && flags+=(-msse4.1)
    compile "$work/obj-$arch" "${flags[@]}"
    xcrun libtool -static -no_warning_for_no_symbols -o "$work/libwebp-$arch.a" "$work/obj-$arch"/*.o
    slices+=("$work/libwebp-$arch.a")
  done
  xcrun lipo -create "${slices[@]}" -output "$out/lib/libwebp.a"
  xcrun lipo -info "$out/lib/libwebp.a"
else
  compile "$work/obj" "${CC:-cc}" -fPIC "${common[@]}"
  ar rcs "$out/lib/libwebp.a" "$work/obj"/*.o
fi

cp "$src"/src/webp/{encode,decode,types}.h "$out/include/webp/"
cp "$src/COPYING" "$out/COPYING"
echo "$stamp" > "$out/.built"
echo "libwebp $WEBP_VERSION → $out"
