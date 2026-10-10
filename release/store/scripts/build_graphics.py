"""Compose store artwork from approved brand files and a redacted real UI capture.
No generated or reconstructed UI. Requires Pillow. Run from repository root.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, hashlib
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'release/store'
INK='#211b16'; IVORY='#f6efdd'; ORANGE='#ff7318'
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'
BOLD='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
def font(n,bold=False): return ImageFont.truetype(BOLD if bold else FONT,n)
def text(d,xy,s,size,color=INK,bold=False): d.text(xy,s,font=font(size,bold),fill=color)
def fitted(im,w,h):
 k=min(w/im.width,h/im.height)
 return im.resize((round(im.width*k),round(im.height*k)),Image.Resampling.LANCZOS)
panel=Image.open(OUT/'sources/macos-connected-redacted.png').convert('RGB')
# Mac format verified against Apple screenshot specifications, 16:10.
im=Image.new('RGB',(2880,1800),IVORY);d=ImageDraw.Draw(im)
text(d,(180,175),'Tetherly',64,bold=True)
d.line((180,300,480,300),fill=ORANGE,width=10)
text(d,(180,495),'Your Mac,',116,bold=True)
text(d,(180,635),'within reach.',116,bold=True)
text(d,(185,855),'Connect from your phone.',48)
text(d,(185,930),'Keep control on your Mac.',48)
text(d,(185,1440),'Mac host  /  Android controller',34)
text(d,(185,1510),'tetherly.link',34)
p=fitted(panel,1120,1250);im.paste(p,(1575,round((1800-p.height)/2)))
text(d,(1575,1555),'Actual Tetherly UI. Network address redacted.',27)
im.save(OUT/'mac-app-store/screenshots/01-connected-2880x1800.png')
# Feature graphic is brand artwork, not a simulated screenshot.
im=Image.new('RGB',(1024,500),IVORY);d=ImageDraw.Draw(im)
d.rounded_rectangle((68,73,954,427),radius=36,fill=ORANGE)
text(d,(108,101),'Tetherly',30,bold=True)
text(d,(108,175),'Your Mac,',68,bold=True)
text(d,(108,255),'within reach.',68,bold=True)
text(d,(112,367),'Control your Mac from your phone',25)
# Abstract connection motif. It contains no app controls or device mockups.
d.arc((796,150,907,261),270,90,fill=IVORY,width=13)
d.arc((745,229,856,340),90,270,fill=IVORY,width=13)
d.line((789,245,863,245),fill=IVORY,width=13)
im.save(OUT/'google-play/graphics/feature-1024x500.png')
print('Wrote Mac screenshot composition and Google Play feature graphic.')
