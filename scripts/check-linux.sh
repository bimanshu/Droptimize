#!/usr/bin/env bash
# What can be checked without a Mac (for agents working in Linux containers):
#   1. every Swift file parses;
#   2. the portable logic (layout, spring, dock position, action menus) passes its unit tests.
# This is NOT a build: AppKit/SwiftUI code is only type-checked by Xcode or by CI
# (.github/workflows/build.yml). Needs a Swift toolchain on PATH; see HANDOFF.md.
set -euo pipefail
cd "$(dirname "$0")/.."

# Foundation-only sources and the tests that cover them. Keep in sync when adding portable code.
PORTABLE_SOURCES=(
  Bubble/Motion.swift
  Bubble/BubbleLayout.swift
  Bubble/DockPosition.swift
  Bubble/Spring.swift
  Pipeline/Action.swift
  Pipeline/Job.swift
)
PORTABLE_TESTS=(
  Tests/LayoutTests.swift
  Tests/DockPositionTests.swift
  Tests/SpringTests.swift
  Tests/ActionTests.swift
)

command -v swiftc >/dev/null || { echo "swiftc not found. See HANDOFF.md → 'Checking code without a Mac'." >&2; exit 1; }

echo "→ Parsing every Swift file"
find App Bubble Pipeline Tests -name '*.swift' -print0 | xargs -0 swiftc -parse
echo "  ok"

echo "→ Running portable unit tests"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Sources/Droptimize" "$work/Tests/DroptimizeTests"
for f in "${PORTABLE_SOURCES[@]}"; do cp "$f" "$work/Sources/Droptimize/"; done
for f in "${PORTABLE_TESTS[@]}"; do cp "$f" "$work/Tests/DroptimizeTests/"; done
# Linux Foundation has CGPoint/CGSize/CGRect but no CGVector.
cat > "$work/Sources/Droptimize/LinuxShims.swift" <<'EOF'
import Foundation
#if !canImport(CoreGraphics)
public struct CGVector: Equatable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
    public static let zero = CGVector(dx: CGFloat(0), dy: CGFloat(0))
}
#endif
EOF
cat > "$work/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Droptimize",
    targets: [
        .target(name: "Droptimize", swiftSettings: [.unsafeFlags(["-swift-version", "5"])]),
        .testTarget(name: "DroptimizeTests", dependencies: ["Droptimize"]),
    ]
)
EOF
if (cd "$work" && swift test >"$work/test.log" 2>&1); then
  grep -E "Executed [0-9]+ tests" "$work/test.log" | tail -1
  echo "  ok"
else
  grep -Ev '^\[[0-9]+/[0-9]+\]' "$work/test.log" >&2
  echo "  FAILED" >&2
  exit 1
fi
