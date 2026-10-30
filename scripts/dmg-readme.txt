Droptimize (preview)

1. Drag Droptimize into the Applications folder.

2. The app isn't notarized by Apple yet, so macOS blocks it the first time.
   Open Terminal and run:

       xattr -cr /Applications/Droptimize.app

   Or: open the app, click Done, then go to System Settings > Privacy & Security
   and click Open Anyway.

3. Open Droptimize. It has no window and no Dock icon. Look for the drop icon
   in the menu bar and the bubble on the right edge of your screen.

Needs macOS 14 (Sonoma) or newer.

To try it: drag an image from Finder onto the bubble, move over a segment,
and let go. The actions are pretend in this preview; nothing is changed or created.
Hold Option while dropping to see the error state. Hide or show the bubble with
Control-Option-Command-D.
