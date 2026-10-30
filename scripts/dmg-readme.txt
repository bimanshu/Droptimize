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

To use it: drag an image from Finder onto the bubble, move over a button, and let go.
  WebP       converts to WebP (the center, Auto, does the same for now)
  Compress   makes it smaller in the same format (JPEG, PNG, WebP, HEIC)
  Half size  halves the width and height, for 2x screenshots
The new file is saved next to the original (which is never changed) and copied to your
clipboard. AVIF, Remove BG and video are coming soon.

The first time it saves into Desktop, Documents or Downloads, macOS asks whether
Droptimize may access that folder. Click Allow. (Each new preview build may ask again.)

Hide or show the bubble with Control-Option-Command-D.

To update later, you don't need this disk image. Paste this into Terminal:

    curl -fsSL https://github.com/bimanshu/Droptimize/releases/download/preview/install.sh | bash
