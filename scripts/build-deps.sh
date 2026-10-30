#!/usr/bin/env bash
# Builds pinned native dependencies into Vendor/ (CORE.md §8). Vendor/ is generated, not committed.
#
#   macOS: universal (arm64 + x86_64) static libraries for the app. Runs automatically from
#          `xcodegen generate` (project.yml preGenCommand) and in CI.
#   Linux: host-only builds, so scripts/check-linux.sh can test the encoders without a Mac.
#
# Each library is skipped when its pinned version is already built. Needs curl, git, a C
# compiler (Xcode's on macOS) and, for AVIF, cmake and perl. nasm makes libaom fast on Intel
# Macs (`brew install nasm`); without it, the Intel slice is built without SIMD.
set -euo pipefail
cd "$(dirname "$0")/.."
# Mind macOS's bash 3.2: declare local arrays first, then assign (`local a=(…)` makes a string there).

# libwebp: WebP encoding. BSD-3-Clause. Approved by the owner 2026-10-30.
WEBP_VERSION=1.6.0
WEBP_SHA256=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
WEBP_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${WEBP_VERSION}.tar.gz"

# libaom: the AV1 encoder inside AVIF. BSD-2-Clause + AOM Patent License 1.0 (royalty-free).
# libavif: reads and writes the AVIF container. BSD-2-Clause. Both approved by the owner 2026-10-30.
AOM_VERSION=3.15.2
AOM_SHA256=67bb54b245f33ed98600e08269e6139986e48114e14042474ddd8885801dfddc
AOM_URL="https://storage.googleapis.com/aom-releases/libaom-${AOM_VERSION}.tar.gz"
AVIF_VERSION=1.4.2
AVIF_COMMIT=c5240fc79fe5c2407e10afd35f5505ef6333ea49     # tag v1.4.2
AVIF_REPO=https://github.com/AOMediaCodec/libavif

MIN_MACOS=14.0
platform="$(uname -s)"
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# up_to_date <dir> <stamp>: whether <dir> already holds this build.
up_to_date() { [[ -f "$1/.built" && "$(cat "$1/.built")" == "$2" ]]; }

# fetch <url> <sha256> <dest>: downloads and checks a release tarball.
fetch() {
  curl -fsSL "$1" -o "$3"
  if command -v shasum >/dev/null; then sum=(shasum -a 256); else sum=(sha256sum); fi
  echo "$2  $3" | "${sum[@]}" -c - >/dev/null
}

# MARK: libwebp

build_webp() {
  local out=Vendor/libwebp stamp="$WEBP_VERSION-$platform"
  up_to_date "$out" "$stamp" && return
  echo "Building libwebp $WEBP_VERSION ($platform)…"
  fetch "$WEBP_URL" "$WEBP_SHA256" "$work/libwebp.tar.gz"
  tar xzf "$work/libwebp.tar.gz" -C "$work"
  local src="$work/libwebp-$WEBP_VERSION"

  # The encoder, the decoder (used by tests), and their shared code. No mux/demux: no animation yet.
  local sources
  sources=("$src"/src/{dec,enc,dsp,utils}/*.c "$src"/sharpyuv/*.c)

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

  local common
  common=(-O2 -DNDEBUG -DWEBP_USE_THREAD -I "$src" -w)
  rm -rf "$out"
  mkdir -p "$out/lib" "$out/include/webp"
  if [[ "$platform" == Darwin ]]; then
    local slices
    slices=()
    for arch in arm64 x86_64; do
      local flags
      flags=(xcrun clang -arch "$arch" -mmacosx-version-min="$MIN_MACOS" "${common[@]}")
      # Every Intel Mac that runs macOS 14 has SSE4.1, so use it everywhere.
      [[ "$arch" == x86_64 ]] && flags+=(-msse4.1)
      compile "$work/webp-obj-$arch" "${flags[@]}"
      xcrun libtool -static -no_warning_for_no_symbols -o "$work/libwebp-$arch.a" "$work/webp-obj-$arch"/*.o
      slices+=("$work/libwebp-$arch.a")
    done
    xcrun lipo -create "${slices[@]}" -output "$out/lib/libwebp.a"
  else
    compile "$work/webp-obj" "${CC:-cc}" -fPIC "${common[@]}"
    ar rcs "$out/lib/libwebp.a" "$work/webp-obj"/*.o
  fi
  cp "$src"/src/webp/{encode,decode,types}.h "$out/include/webp/"
  cp "$src/COPYING" "$out/COPYING"
  echo "$stamp" > "$out/.built"
  echo "libwebp $WEBP_VERSION → $out"
}

# MARK: libaom + libavif

# build_avif_slice <arch or "host"> <prefix>: libaom, then libavif on top of it, installed into <prefix>.
build_avif_slice() {
  local arch=$1 prefix=$2
  local aom_src="$work/libaom-$AOM_VERSION" avif_src="$work/libavif"
  local cmake_common
  cmake_common=(-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$prefix"
                -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_POSITION_INDEPENDENT_CODE=ON)
  local aom_flags
  aom_flags=(-DENABLE_TESTS=0 -DENABLE_EXAMPLES=0 -DENABLE_TOOLS=0 -DENABLE_DOCS=0 -DENABLE_TESTDATA=0)
  local avif_flags
  avif_flags=(-DAVIF_CODEC_AOM=SYSTEM -DAVIF_LIBYUV=OFF -DAVIF_LIBSHARPYUV=OFF -DAVIF_JPEG=OFF
              -DAVIF_ZLIBPNG=OFF -DAVIF_BUILD_APPS=OFF -DAVIF_BUILD_TESTS=OFF
              -DAOM_INCLUDE_DIR="$prefix/include" -DAOM_LIBRARY="$prefix/lib/libaom.a")
  if [[ "$arch" != host ]]; then
    cmake_common+=(-DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS")
    aom_flags+=(-DCMAKE_TOOLCHAIN_FILE="$aom_src/cmake/toolchains/$arch-macos.cmake")
    if [[ "$arch" == x86_64 ]] && ! command -v nasm >/dev/null; then
      echo "  (nasm not found: the Intel slice of libaom is built without SIMD, so it's slower. brew install nasm)"
      aom_flags+=(-DAOM_TARGET_CPU=generic)
    fi
  fi
  cmake -S "$aom_src" -B "$work/aom-build-$arch" -Wno-dev "${cmake_common[@]}" "${aom_flags[@]}" >"$work/aom-$arch.log" 2>&1 \
    || { tail -30 "$work/aom-$arch.log"; exit 1; }
  cmake --build "$work/aom-build-$arch" -j "$jobs" >>"$work/aom-$arch.log" 2>&1 || { tail -30 "$work/aom-$arch.log"; exit 1; }
  cmake --install "$work/aom-build-$arch" >>"$work/aom-$arch.log" 2>&1

  cmake -S "$avif_src" -B "$work/avif-build-$arch" -Wno-dev "${cmake_common[@]}" "${avif_flags[@]}" >"$work/avif-$arch.log" 2>&1 \
    || { tail -30 "$work/avif-$arch.log"; exit 1; }
  cmake --build "$work/avif-build-$arch" -j "$jobs" >>"$work/avif-$arch.log" 2>&1 || { tail -30 "$work/avif-$arch.log"; exit 1; }
  cmake --install "$work/avif-build-$arch" >>"$work/avif-$arch.log" 2>&1
}

build_avif() {
  local out=Vendor/libavif stamp="$AVIF_VERSION-aom$AOM_VERSION-$platform"
  up_to_date "$out" "$stamp" && return
  command -v cmake >/dev/null || { echo "cmake is needed to build AVIF support (brew install cmake)." >&2; exit 1; }
  echo "Building libaom $AOM_VERSION and libavif $AVIF_VERSION ($platform). This takes a few minutes, once…"
  fetch "$AOM_URL" "$AOM_SHA256" "$work/libaom.tar.gz"
  tar xzf "$work/libaom.tar.gz" -C "$work"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "v$AVIF_VERSION" "$AVIF_REPO" "$work/libavif"
  [[ "$(git -C "$work/libavif" rev-parse HEAD)" == "$AVIF_COMMIT" ]] || { echo "libavif v$AVIF_VERSION isn't the pinned commit" >&2; exit 1; }

  rm -rf "$out"
  mkdir -p "$out/lib" "$out/include"
  if [[ "$platform" == Darwin ]]; then
    for arch in arm64 x86_64; do build_avif_slice "$arch" "$work/avif-$arch"; done
    for lib in libaom.a libavif.a; do
      xcrun lipo -create "$work/avif-arm64/lib/$lib" "$work/avif-x86_64/lib/$lib" -output "$out/lib/$lib"
    done
    cp -R "$work/avif-arm64/include/avif" "$out/include/"
  else
    build_avif_slice host "$work/avif-host"
    cp "$work/avif-host/lib/"{libaom.a,libavif.a} "$out/lib/"
    cp -R "$work/avif-host/include/avif" "$out/include/"
  fi
  cp "$work/libaom-$AOM_VERSION/LICENSE" "$out/LICENSE-aom"
  cp "$work/libaom-$AOM_VERSION/PATENTS" "$out/PATENTS-aom"
  cp "$work/libavif/LICENSE" "$out/LICENSE-avif"
  echo "$stamp" > "$out/.built"
  echo "libaom $AOM_VERSION + libavif $AVIF_VERSION → $out"
}

build_webp
build_avif
