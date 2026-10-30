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
  Convert    keep holding over it and pick a format: WebP, AVIF, JPG, PNG or HEIC.
             (Let go on Convert itself, or the center, for WebP.)
  Compress   makes it smaller in the same format (JPEG, PNG, WebP, HEIC, AVIF).
             Keep holding over it and smaller bubbles appear: pick a size
             (100K to 2M), or ... to type your own after you let go.
  Half size  halves the width and height, for 2x screenshots
  Remove BG  cuts out the subject. Its smaller bubbles choose what goes behind:
             none (see-through), white, black, or ... for any hex color.
The new file is saved next to the original (which is never changed) and copied to your
clipboard.

Videos (MOV, MP4, M4V) get their own buttons:
  Convert    MP4 (instant when the video is already H.264), HEVC, or GIF (a looping
             GIF of up to the first 30 seconds).
  Compress   smaller, same type. Its bubbles pick a size: 10, 25, 50 or 100 MB, or ...
             for your own. Very small sizes lower the resolution, and it says so.
  Resize     1080p, 720p or 480p. Never makes a video bigger than it is.
  Mute       removes the sound, without re-encoding.
  The center (Auto) makes a smaller MP4. Videos take a while: the ring shows progress,
  and clicking the bubble cancels.

The first time it saves into Desktop, Documents or Downloads, macOS asks whether
Droptimize may access that folder. Click Allow. (Each new preview build may ask again.)

Everything you make is listed in History (click the drop icon in the menu bar).
Hide or show the bubble with Control-Option-Command-D.

To update later, you don't need this disk image. Paste this into Terminal:

    curl -fsSL https://github.com/bimanshu/Droptimize/releases/download/preview/install.sh | bash
