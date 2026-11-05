#!/usr/bin/env bash
# Builds pinned native dependencies into Vendor/ (CORE.md §8). Vendor/ is generated, not committed.
#
#   macOS: universal (arm64 + x86_64) static libraries for the app. Runs automatically from
#          `xcodegen generate` (project.yml preGenCommand) and in CI.
#   Linux: host-only builds, so scripts/check-linux.sh can test the encoders without a Mac.
#
# Each library is skipped when its pinned version is already built. Needs curl, git, make, a C
# compiler (Xcode's on macOS), cmake and perl. nasm makes libaom and libvpx fast on Intel
# (`brew install nasm`); without it, their Intel slices are built without SIMD.
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

# libvpx: the VP9 encoder for WebM video. BSD-3-Clause + Google's royalty-free VP8/VP9 patent grant.
# libopus: the sound in WebM. BSD-3-Clause (+ royalty-free patent licenses). Both approved by the
# owner 2026-11-05. AV1 video reuses the libaom above. The WebM container is our own (Video/WebMWriter.swift).
VPX_VERSION=1.17.0
VPX_SHA256=7f98aae5c52c46e85b7b26feabcab9b1554605e771bd1df1d6e6a00ee22fa8ed
VPX_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webm/libvpx-${VPX_VERSION}.tar.gz"
OPUS_VERSION=1.5.2
OPUS_SHA256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
OPUS_URL="https://github.com/xiph/opus/releases/download/v${OPUS_VERSION}/opus-${OPUS_VERSION}.tar.gz"

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
  # "+aomh": the libaom headers are installed too (AV1 video talks to libaom directly).
  local out=Vendor/libavif stamp="$AVIF_VERSION-aom$AOM_VERSION+aomh-$platform"
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
    cp -R "$work/avif-arm64/include/"{avif,aom} "$out/include/"
  else
    build_avif_slice host "$work/avif-host"
    cp "$work/avif-host/lib/"{libaom.a,libavif.a} "$out/lib/"
    cp -R "$work/avif-host/include/"{avif,aom} "$out/include/"
  fi
  cp "$work/libaom-$AOM_VERSION/LICENSE" "$out/LICENSE-aom"
  cp "$work/libaom-$AOM_VERSION/PATENTS" "$out/PATENTS-aom"
  cp "$work/libavif/LICENSE" "$out/LICENSE-avif"
  echo "$stamp" > "$out/.built"
  echo "libaom $AOM_VERSION + libavif $AVIF_VERSION → $out"
}

# MARK: libvpx

# build_vpx_slice <arch or "host"> <prefix>: libvpx's VP9 encoder only, installed into <prefix>.
build_vpx_slice() {
  local arch=$1 prefix=$2
  local build="$work/vpx-build-$arch"
  local flags
  flags=(--prefix="$prefix" --enable-static --disable-shared --enable-pic --disable-vp8 --disable-vp9-decoder
         --disable-examples --disable-tools --disable-docs --disable-unit-tests --disable-webm-io --disable-libyuv)
  if [[ "$arch" == arm64 ]]; then
    flags+=(--target=arm64-darwin23-gcc --extra-cflags="-mmacosx-version-min=$MIN_MACOS")
  elif [[ "$arch" == x86_64 ]]; then
    if command -v nasm >/dev/null; then
      flags+=(--target=x86_64-darwin23-gcc --as=nasm --extra-cflags="-mmacosx-version-min=$MIN_MACOS")
    else
      echo "  (nasm not found: the Intel slice of libvpx is built without SIMD, so it's slower. brew install nasm)"
      flags+=(--target=generic-gnu --extra-cflags="-arch x86_64 -mmacosx-version-min=$MIN_MACOS")
    fi
  fi
  mkdir -p "$build"
  (cd "$build" && "$work/libvpx-$VPX_VERSION/configure" "${flags[@]}") >"$work/vpx-$arch.log" 2>&1 \
    || { tail -30 "$work/vpx-$arch.log"; exit 1; }
  make -C "$build" -j "$jobs" install >>"$work/vpx-$arch.log" 2>&1 || { tail -30 "$work/vpx-$arch.log"; exit 1; }
}

build_vpx() {
  local out=Vendor/libvpx stamp="$VPX_VERSION-$platform"
  up_to_date "$out" "$stamp" && return
  echo "Building libvpx $VPX_VERSION ($platform). This takes a minute or two, once…"
  fetch "$VPX_URL" "$VPX_SHA256" "$work/libvpx.tar.gz"
  tar xzf "$work/libvpx.tar.gz" -C "$work"
  rm -rf "$out"
  mkdir -p "$out/lib" "$out/include"
  if [[ "$platform" == Darwin ]]; then
    for arch in arm64 x86_64; do build_vpx_slice "$arch" "$work/vpx-$arch"; done
    xcrun lipo -create "$work/vpx-arm64/lib/libvpx.a" "$work/vpx-x86_64/lib/libvpx.a" -output "$out/lib/libvpx.a"
    cp -R "$work/vpx-arm64/include/vpx" "$out/include/"
  else
    build_vpx_slice host "$work/vpx-host"
    cp "$work/vpx-host/lib/libvpx.a" "$out/lib/"
    cp -R "$work/vpx-host/include/vpx" "$out/include/"
  fi
  cp "$work/libvpx-$VPX_VERSION/LICENSE" "$out/LICENSE"
  cp "$work/libvpx-$VPX_VERSION/PATENTS" "$out/PATENTS"
  echo "$stamp" > "$out/.built"
  echo "libvpx $VPX_VERSION → $out"
}

# MARK: libopus

# build_opus_slice <arch or "host"> <prefix>
build_opus_slice() {
  local arch=$1 prefix=$2
  local flags
  flags=(-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$prefix"
         -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_POSITION_INDEPENDENT_CODE=ON
         -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_INSTALL_PKG_CONFIG_MODULE=OFF
         -DOPUS_INSTALL_CMAKE_CONFIG_MODULE=OFF)
  if [[ "$arch" != host ]]; then
    # Opus picks its SIMD code from CMAKE_SYSTEM_PROCESSOR, which is the build machine's unless
    # cross-compiling is declared. "aarch64" also tells it every Apple Silicon Mac has NEON.
    local processor=$arch
    [[ "$arch" == arm64 ]] && processor=aarch64
    flags+=(-DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS"
            -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR="$processor")
  fi
  cmake -S "$work/opus-$OPUS_VERSION" -B "$work/opus-build-$arch" -Wno-dev "${flags[@]}" >"$work/opus-$arch.log" 2>&1 \
    || { tail -30 "$work/opus-$arch.log"; exit 1; }
  cmake --build "$work/opus-build-$arch" -j "$jobs" >>"$work/opus-$arch.log" 2>&1 || { tail -30 "$work/opus-$arch.log"; exit 1; }
  cmake --install "$work/opus-build-$arch" >>"$work/opus-$arch.log" 2>&1
}

build_opus() {
  local out=Vendor/libopus stamp="$OPUS_VERSION-$platform"
  up_to_date "$out" "$stamp" && return
  command -v cmake >/dev/null || { echo "cmake is needed to build Opus (brew install cmake)." >&2; exit 1; }
  echo "Building libopus $OPUS_VERSION ($platform)…"
  fetch "$OPUS_URL" "$OPUS_SHA256" "$work/opus.tar.gz"
  tar xzf "$work/opus.tar.gz" -C "$work"
  rm -rf "$out"
  mkdir -p "$out/lib" "$out/include"
  if [[ "$platform" == Darwin ]]; then
    for arch in arm64 x86_64; do build_opus_slice "$arch" "$work/opus-$arch"; done
    xcrun lipo -create "$work/opus-arm64/lib/libopus.a" "$work/opus-x86_64/lib/libopus.a" -output "$out/lib/libopus.a"
    cp -R "$work/opus-arm64/include/opus" "$out/include/"
  else
    build_opus_slice host "$work/opus-host"
    cp "$work/opus-host/lib/libopus.a" "$out/lib/"
    cp -R "$work/opus-host/include/opus" "$out/include/"
  fi
  cp "$work/opus-$OPUS_VERSION/COPYING" "$out/COPYING"
  echo "$stamp" > "$out/.built"
  echo "libopus $OPUS_VERSION → $out"
}

build_webp
build_avif
build_vpx
build_opus
