# Droptimize: instructions for agents

A native macOS app: drag an image or video onto a small floating bubble, let go on a radial menu, and get a smaller, web-ready file back.

**At the start of every session, read these in order:**

1. `HANDOFF.md`: where the work stands right now. Continue from its **Next steps**.
2. `CORE.md`: the spec and the rules. The §3 Rules are decisions, not suggestions.

**Whenever you stop (finished, blocked or out of time):**

1. Update the ✱ sections of `HANDOFF.md` so another agent could carry on with nothing else to go on.
2. Update `CORE.md`: §1 Status, a line in §14 Changelog (newest first), and any new questions in §13 Open decisions.
3. Run the checks, commit, push to your branch, and check CI.

**Quick facts**

- Build on a Mac with `xcodegen generate`, then Xcode or `xcodebuild`. In a Linux container, `scripts/check-linux.sh` parses every file and runs the portable tests. CI (`.github/workflows/build.yml`) is the real compile check.
- Every motion and sizing constant lives in `Bubble/Motion.swift`.
- Before adding a dependency, state its license and ask the owner. Also ask before changing anything that affects licensing, distribution or how the interaction feels.
