"""Draws the 全心日記 app icon: goose-yellow background, a heart-shaped letter, a quill writing on it.

    python make_icon.py <out dir>

Writes (1024×1024 PNG):
  icon_1024.png                 full icon (legacy launchers, Play Store)
  adaptive_foreground_1024.png  artwork only, shrunk into the adaptive-icon safe zone
  adaptive_monochrome_1024.png  one-colour silhouette for Android 13 themed icons
and .svg files for the two colour ones, so the drawing can be reviewed or edited.

Needs cairosvg (and the cairo library) and Pillow. The source of truth is this script, not the PNGs.
"""

from __future__ import annotations

import sys
from pathlib import Path

import io

import cairosvg
from PIL import Image, ImageChops

YELLOW = "#F6D365"
YELLOW_LIGHT = "#FBE6A6"
YELLOW_DEEP = "#E4B53F"
PAPER = "#FFF9EE"
PAPER_EDGE = "#E9D9B8"
LINE = "#E8D3A6"
INK = "#5A3E1B"
SHAFT = "#9B6F1E"
FEATHER = "#FFFFFF"
FEATHER_SHADE = "#F1E6CF"

# Size of the artwork in the adaptive layers (see main()).
ADAPTIVE_SCALE = 0.97

# Heart in a 100×100 box (point at the bottom).
HEART = ("M50,92 C22,73 2,55 2,32 C2,14 15,3 30,3 C40,3 46,9 50,17 "
         "C54,9 60,3 70,3 C85,3 98,14 98,32 C98,55 78,73 50,92 Z")


VANE = ("M2,-130 C70,-210 96,-400 24,-560 C6,-520 -30,-470 -48,-400 "
        "C-66,-330 -62,-240 -40,-190 C-26,-160 -12,-140 2,-130 Z")
NIB = "M-11,-128 L11,-128 L6,-30 L0,0 L-6,-30 Z"
SHAFT_PATH = "M0,-40 C2,-200 8,-380 22,-552"
HEART_AT = 'transform="translate(222,250) scale(5.6)"'
TILT = 'transform="rotate(-8 512 520)"'
QUILL_AT = 'transform="translate(600,566) rotate(30)"'
RULED = (430, 500, 570, 640)


def quill() -> str:
    """The quill in colour, drawn pointing straight up from its nib at (0,0)."""
    q = [f'<path d="{VANE}" fill="{FEATHER}" stroke="{FEATHER_SHADE}" stroke-width="6"/>',
         # The far side of the vane in a slightly darker cream, then a few faint barbs.
         f'<path d="M2,-130 C-12,-140 -26,-160 -40,-190 C-62,-240 -66,-330 -48,-400 '
         f'C-30,-470 6,-520 24,-560 C-6,-470 -14,-330 2,-130 Z" fill="{FEATHER_SHADE}"/>',
         f'<clipPath id="vaneClip"><path d="{VANE}"/></clipPath>',
         f'<g clip-path="url(#vaneClip)" stroke="{PAPER_EDGE}" stroke-width="3" stroke-linecap="round" opacity="0.55">']
    for y in range(-200, -520, -64):
        q.append(f'<line x1="{6 + (y + 130) * -0.03:.0f}" y1="{y}" x2="90" y2="{y - 70}"/>')
        q.append(f'<line x1="{4 + (y + 130) * -0.03:.0f}" y1="{y}" x2="-70" y2="{y - 60}"/>')
    q.append("</g>")
    q.append(f'<path d="{SHAFT_PATH}" fill="none" stroke="{SHAFT}" stroke-width="10" stroke-linecap="round"/>')
    q.append(f'<path d="{NIB}" fill="{INK}"/>')
    q.append(f'<line x1="0" y1="-60" x2="0" y2="-12" stroke="{PAPER}" stroke-width="3"/>')
    return "".join(q)


def artwork() -> str:
    """The heart letter and quill in colour, for a 1024 canvas."""
    parts = [f'<g {TILT}>',
             # Heart letter: flat shadow, paper, ruled lines clipped to the heart, a line of writing.
             f'<path d="{HEART}" transform="translate(236,268) scale(5.6)" fill="{YELLOW_DEEP}" opacity="0.55"/>',
             f'<path d="{HEART}" {HEART_AT} fill="{PAPER}" stroke="{PAPER_EDGE}" stroke-width="0.6"/>',
             f'<clipPath id="heartClip"><path d="{HEART}" {HEART_AT}/></clipPath>',
             f'<g clip-path="url(#heartClip)" stroke="{LINE}" stroke-width="9" stroke-linecap="round">']
    parts += [f'<line x1="300" y1="{y}" x2="724" y2="{y}"/>' for y in RULED]
    parts.append("</g>")
    parts.append(f'<path d="M352,568 c22,-24 40,24 62,0 s40,24 62,0 s40,22 62,0 s34,18 56,4" fill="none" '
                 f'stroke="{INK}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>')
    parts.append("</g>")
    parts.append(f'<g {QUILL_AT}>{quill()}</g>')
    # The heart sits low-left and the quill reaches up-right; shift so the pair is centred.
    return f'<g transform="translate(-44,62)">{"".join(parts)}</g>'


def monochrome_layers() -> tuple[str, str, str]:
    """One-colour version for themed icons (Android uses only its alpha). A plain silhouette merges
    quill and heart into one blob, so the heart gets a gap cut around the quill and three ruled lines
    cut out. Returned as three layers — heart, cut, quill — composited in main() (cairosvg doesn't
    render SVG masks)."""
    shift = 'transform="translate(-44,62)"'
    heart = f'<g {shift}><g {TILT}><path d="{HEART}" {HEART_AT} fill="#fff"/></g></g>'
    cut = (f'<g {shift}><g {TILT} stroke="#fff" stroke-width="22" stroke-linecap="round">'
           + "".join(f'<line x1="300" y1="{y}" x2="724" y2="{y}"/>' for y in RULED[1:])
           + f'</g><g {QUILL_AT} fill="#fff" stroke="#fff" stroke-width="44" stroke-linejoin="round">'
           f'<path d="{VANE}"/><path d="{NIB}"/></g></g>')
    quill_shape = f'<g {shift}><g {QUILL_AT} fill="#fff"><path d="{VANE}"/><path d="{NIB}"/></g></g>'
    return heart, cut, quill_shape


def svg(body: str, background: str | None) -> str:
    bg = ""
    if background == "gradient":
        bg = (f'<defs><radialGradient id="bg" cx="50%" cy="42%" r="70%">'
              f'<stop offset="0" stop-color="{YELLOW_LIGHT}"/><stop offset="1" stop-color="{YELLOW}"/>'
              f'</radialGradient></defs><rect width="1024" height="1024" fill="url(#bg)"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{bg}{body}</svg>'


def scaled(body: str, factor: float) -> str:
    """Shrink the artwork about the centre (adaptive icons crop to the middle ~61%)."""
    offset = 512 * (1 - factor)
    return f'<g transform="translate({offset:.1f},{offset:.1f}) scale({factor})">{body}</g>'


def render(text: str) -> Image.Image:
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=text.encode(), output_width=1024, output_height=1024))).convert("RGBA")


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)
    files = {
        # Legacy icon: the launcher shows the whole square (often with rounded corners).
        "icon_1024": svg(scaled(artwork(), 0.92), "gradient"),
        # Adaptive foreground: only a centred circle of 66/108 of the layer is guaranteed visible.
        # flutter_launcher_icons already insets this image by 16% on each side (it fills 68% of the
        # layer), so the safe circle is 66/68 of this image: radius ≈ 497 px. The farthest point, the
        # quill's tip, sits ~456 px from the centre, so the artwork fits at 0.97 with a little margin.
        "adaptive_foreground_1024": svg(scaled(artwork(), ADAPTIVE_SCALE), None),
    }
    for name, text in files.items():
        (out / f"{name}.svg").write_text(text, encoding="utf-8")
        render(text).save(out / f"{name}.png")
        print("wrote", out / f"{name}.png")

    heart, cut, quill_shape = (render(svg(scaled(layer, ADAPTIVE_SCALE), None)).getchannel("A") for layer in monochrome_layers())
    alpha = ImageChops.lighter(ImageChops.subtract(heart, cut), quill_shape)
    mono = Image.new("RGBA", (1024, 1024), (255, 255, 255, 0))
    mono.putalpha(alpha)
    mono.save(out / "adaptive_monochrome_1024.png")
    print("wrote", out / "adaptive_monochrome_1024.png")


if __name__ == "__main__":
    main()
