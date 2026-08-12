#!/usr/bin/env python3
"""scripts/e2e/ocr.py <ppm> — PPM -> PNG (2x LANCZOS) -> tesseract text (stdout).
Requires: python3-pil, tesseract-ocr on the HOST.
"""
from PIL import Image
import subprocess, sys

p = sys.argv[1]
with open(p, 'rb') as f:
    f.readline()               # magic
    dims = f.readline().strip()
    f.readline()               # maxval
    w, h = map(int, dims.split())
    px = f.read()
img = Image.frombytes('RGB', (w, h), px)
img = img.resize((w * 2, h * 2), Image.LANCZOS)
png = p + '.png'
img.save(png)
out = subprocess.run(['tesseract', png, 'stdout', '--psm', '6'],
                     capture_output=True, text=True)
print(out.stdout)
