"""Downloads the extra photos film v9 uses into images/ (git-ignored). Run after prepare-images-v4.py,
from docs/launch-video/film/:

    python3 prepare-images-v4.py && python3 prepare-images-v9.py

All from Pexels (free for commercial use, no credit required; owner: "not the most common images"):
  river    12756665  https://www.pexels.com/photo/aerial-view-of-a-landscape-12756665/
  dune     28829633  https://www.pexels.com/photo/majestic-sand-dunes-at-sunset-in-sahara-desert-28829633/
  ripples  19896998  https://www.pexels.com/photo/shadow-on-sunlit-desert-19896998/
  blocks   18075296  https://www.pexels.com/photo/modern-multi-colored-facade-18075296/
  door     27050620  https://www.pexels.com/photo/a-bright-pink-building-with-blue-shutters-and-a-door-27050620/
  cat      16398478  https://www.pexels.com/photo/orange-cat-sitting-by-the-window-16398478/
  road     34889618  https://www.pexels.com/photo/foggy-road-through-a-dark-forest-in-autumn-34889618/
  latte    347144    https://www.pexels.com/photo/white-ceramic-teacup-on-table-347144/
  tabby    1170986   https://www.pexels.com/photo/selective-focus-photography-of-orange-tabby-cat-1170986/
  wall     38921436  https://www.pexels.com/photo/minimalistic-pink-building-against-blue-sky-38921436/
"""
import os, subprocess
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get('OUT') or os.path.join(HERE, 'images')
PHOTOS = {'river': 12756665, 'dune': 28829633, 'ripples': 19896998, 'blocks': 18075296, 'door': 27050620,
          'cat': 16398478, 'road': 34889618, 'latte': 347144, 'tabby': 1170986, 'wall': 38921436}
TRIM = {'cat': 0.03}     # that scan has a white film border


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, pid in PHOTOS.items():
        src = os.path.join(OUT, f'src_{key}.jpg')
        url = f'https://images.pexels.com/photos/{pid}/pexels-photo-{pid}.jpeg?auto=compress&cs=tinysrgb&w=1800'
        subprocess.run(['curl', '-fsSL', '--max-time', '60', '-o', src, url], check=True)
        im = Image.open(src).convert('RGB')
        if key in TRIM:
            w, h = im.size; m = TRIM[key]
            im = im.crop((int(w * m), int(h * m), int(w * (1 - m)), int(h * (1 - m))))
        im.thumbnail((1600, 1600), Image.LANCZOS)
        im.save(os.path.join(OUT, f'x-{key}.webp'), quality=90)
        os.remove(src)
    print('wrote', sorted(f for f in os.listdir(OUT) if f.startswith('x-')))


if __name__ == '__main__':
    main()
