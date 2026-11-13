#!/usr/bin/env python3
"""Generates docs/demo.svg, the animated preview used in the README.

The animation uses SMIL so it plays inside an <img> tag on GitHub.
Run: python3 scripts/make-demo-svg.py
"""

from pathlib import Path

W, H = 800, 500
DURATION = 12.0  # seconds per loop

MENU_H = 24
VISIBLE = (0, MENU_H, W, 440 - MENU_H)  # x, y, w, h of the usable screen area

# Window frames (x, y, w, h)
ORIGINAL = (170, 92, 400, 270)
FILL = VISIBLE
LEFT = (0, MENU_H, W // 2, VISIBLE[3])
RIGHT = (W // 2, MENU_H, W // 2, VISIBLE[3])

# Toolbar layout, relative to the window's top left corner
TITLE_H = 30
TB_X, TB_Y = 68, 4
BTN_W, BTN_H, BTN_GAP, TB_PAD = 28, 20, 2, 2
TB_W = TB_PAD * 2 + BTN_W * 3 + BTN_GAP * 2
TB_H = TB_PAD * 2 + BTN_H

EASE = "0.4 0 0.2 1"
LINEAR = "0 0 1 1"


def button_center(frame, index):
    x = frame[0] + TB_X + TB_PAD + index * (BTN_W + BTN_GAP) + BTN_W / 2
    y = frame[1] + TB_Y + TB_PAD + BTN_H / 2
    return (x, y)


FILL_BTN, LEFT_BTN, RIGHT_BTN = 0, 1, 2
CURSOR_HOME = (640, 400)

# Each step: (click time, button, frame before, frame after, caption)
STEPS = [
    (1.4, FILL_BTN, ORIGINAL, FILL, "Fill"),
    (3.6, LEFT_BTN, FILL, LEFT, "Left half"),
    (5.6, RIGHT_BTN, LEFT, RIGHT, "Right half"),
    (8.0, RIGHT_BTN, RIGHT, ORIGINAL, "Click again to restore"),
]
MOVE_TIME = 0.35      # window move
CURSOR_TRAVEL = 1.0   # cursor glide to the next button


def fmt(n):
    return f"{n:.2f}".rstrip("0").rstrip(".")


def animate(attr, keyframes, extra=""):
    """keyframes: list of (time, value string). Eases between differing values."""
    keyframes = sorted(keyframes, key=lambda k: k[0])
    if keyframes[0][0] > 0:
        keyframes.insert(0, (0.0, keyframes[0][1]))
    if keyframes[-1][0] < DURATION:
        keyframes.append((DURATION, keyframes[-1][1]))
    times = ";".join(fmt(t / DURATION) for t, _ in keyframes)
    values = ";".join(v for _, v in keyframes)
    splines = ";".join(
        EASE if a[1] != b[1] else LINEAR for a, b in zip(keyframes, keyframes[1:])
    )
    return (
        f'<animate attributeName="{attr}" dur="{fmt(DURATION)}s" repeatCount="indefinite" '
        f'calcMode="spline" keyTimes="{times}" values="{values}" keySplines="{splines}" {extra}/>'
    )


def animate_translate(keyframes):
    keyframes = sorted(keyframes, key=lambda k: k[0])
    if keyframes[0][0] > 0:
        keyframes.insert(0, (0.0, keyframes[0][1]))
    if keyframes[-1][0] < DURATION:
        keyframes.append((DURATION, keyframes[-1][1]))
    times = ";".join(fmt(t / DURATION) for t, _ in keyframes)
    values = ";".join(f"{fmt(x)} {fmt(y)}" for _, (x, y) in keyframes)
    splines = ";".join(
        EASE if a[1] != b[1] else LINEAR for a, b in zip(keyframes, keyframes[1:])
    )
    return (
        f'<animateTransform attributeName="transform" type="translate" dur="{fmt(DURATION)}s" '
        f'repeatCount="indefinite" calcMode="spline" keyTimes="{times}" values="{values}" keySplines="{splines}"/>'
    )


# ---------- Window keyframes ----------
win_pos, win_w, win_h = [(0, ORIGINAL[:2])], [(0, ORIGINAL[2])], [(0, ORIGINAL[3])]
for click, _, before, after, _ in STEPS:
    start, end = click + 0.1, click + 0.1 + MOVE_TIME
    win_pos += [(start, before[:2]), (end, after[:2])]
    win_w += [(start, before[2]), (end, after[2])]
    win_h += [(start, before[3]), (end, after[3])]

# Toolbar hides while the window moves, like the real app.
tb_opacity = [(0, "1")]
for click, *_ in STEPS:
    tb_opacity += [(click + 0.08, "1"), (click + 0.12, "0"),
                   (click + 0.1 + MOVE_TIME + 0.15, "0"), (click + 0.1 + MOVE_TIME + 0.3, "1")]

# ---------- Cursor keyframes ----------
cursor = [(0, CURSOR_HOME)]
prev = CURSOR_HOME
for click, button, before, _, _ in STEPS:
    target = button_center(before, button)
    arrive = click - 0.2
    cursor += [(arrive - CURSOR_TRAVEL, prev), (arrive, target)]
    prev = target
cursor += [(9.6, prev), (10.8, CURSOR_HOME)]

# ---------- Button highlights ----------
def highlight_frames(index):
    frames = [(0, "0")]
    for click, button, *_ in STEPS:
        if button != index:
            continue
        arrive = click - 0.2
        frames += [(arrive - 0.05, "0"), (arrive, "0.14"), (click - 0.02, "0.14"),
                   (click, "0.32"), (click + 0.1, "0.32"), (click + 0.12, "0")]
    return frames


# ---------- Click ripples and captions ----------
def ripple(click, center):
    cx, cy = center
    times = [0, click - 0.01, click, click + 0.45, DURATION]
    kt = ";".join(fmt(t / DURATION) for t in times)
    return f'''
  <circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="0" fill="none" stroke="#0a84ff" stroke-width="2" opacity="0">
    <animate attributeName="r" dur="{fmt(DURATION)}s" repeatCount="indefinite" keyTimes="{kt}" values="0;0;4;18;18"/>
    <animate attributeName="opacity" dur="{fmt(DURATION)}s" repeatCount="indefinite" keyTimes="{kt}" values="0;0;0.9;0;0"/>
  </circle>'''


def caption(click, text):
    show, hide = click + 0.05, min(click + 1.6, DURATION - 0.01)
    times = [0, show, show + 0.15, hide - 0.2, hide, DURATION]
    kt = ";".join(fmt(t / DURATION) for t in times)
    width = 30 + len(text) * 9.2
    return f'''
  <g opacity="0">
    <animate attributeName="opacity" dur="{fmt(DURATION)}s" repeatCount="indefinite" keyTimes="{kt}" values="0;0;1;1;0;0"/>
    <rect x="{fmt(W / 2 - width / 2)}" y="384" width="{fmt(width)}" height="34" rx="17" fill="#1c1c1e" fill-opacity="0.82"/>
    <text x="{W / 2}" y="406" text-anchor="middle" font-size="15" font-weight="600" fill="#fff">{text}</text>
  </g>'''


# ---------- Static pieces ----------
def icon(kind, x, y):
    """Small window glyphs like the SF Symbols used in the app."""
    w, h = 14, 11
    outline = f'<rect x="{fmt(x + 0.5)}" y="{fmt(y + 0.5)}" width="{w - 1}" height="{h - 1}" rx="2.2" fill="none" stroke="#3a3a3c" stroke-width="1.2"/>'
    if kind == "fill":
        inner = f'<rect x="{fmt(x + 2.5)}" y="{fmt(y + 2.5)}" width="{w - 5}" height="{h - 5}" rx="1" fill="#3a3a3c"/>'
    elif kind == "left":
        inner = f'<rect x="{fmt(x + 2.5)}" y="{fmt(y + 2.5)}" width="{(w - 5) / 2:.1f}" height="{h - 5}" rx="1" fill="#3a3a3c"/>'
    else:
        inner = f'<rect x="{fmt(x + 2.5 + (w - 5) / 2)}" y="{fmt(y + 2.5)}" width="{(w - 5) / 2:.1f}" height="{h - 5}" rx="1" fill="#3a3a3c"/>'
    return outline + inner


def toolbar():
    parts = [f'<g id="toolbar" transform="translate({TB_X} {TB_Y})">',
             animate("opacity", tb_opacity),
             f'<rect width="{TB_W}" height="{TB_H}" rx="7" fill="#ffffff" fill-opacity="0.9" stroke="#000" stroke-opacity="0.12" stroke-width="0.6"/>']
    for i, kind in enumerate(["fill", "left", "right"]):
        bx = TB_PAD + i * (BTN_W + BTN_GAP)
        parts.append(
            f'<rect x="{bx}" y="{TB_PAD}" width="{BTN_W}" height="{BTN_H}" rx="5" fill="#000" opacity="0">'
            + animate("opacity", highlight_frames(i)) + "</rect>"
        )
        parts.append(icon(kind, bx + (BTN_W - 14) / 2, TB_PAD + (BTN_H - 11) / 2))
    parts.append("</g>")
    return "\n    ".join(parts)


def window_contents(width_anim, height_anim):
    return f'''
    <clipPath id="winclip">
      <rect width="{ORIGINAL[2]}" height="{ORIGINAL[3]}" rx="10">
        {width_anim}
        {height_anim}
      </rect>
    </clipPath>
    <g clip-path="url(#winclip)">
      <rect width="{W}" height="{H}" fill="#ffffff"/>
      <rect width="{W}" height="{TITLE_H}" fill="#ececee"/>
      <rect y="{TITLE_H}" width="{W}" height="0.8" fill="#d1d1d6"/>
      <rect y="{TITLE_H + 0.8}" width="120" height="{H}" fill="#f4f4f6"/>
      <rect x="18" y="52" width="70" height="8" rx="4" fill="#d9d9de"/>
      <rect x="18" y="72" width="54" height="8" rx="4" fill="#d9d9de"/>
      <rect x="18" y="92" width="64" height="8" rx="4" fill="#d9d9de"/>
      <rect x="142" y="54" width="180" height="10" rx="5" fill="#e3e3e8"/>
      <rect x="142" y="78" width="240" height="8" rx="4" fill="#ececf0"/>
      <rect x="142" y="96" width="210" height="8" rx="4" fill="#ececf0"/>
      <rect x="142" y="114" width="226" height="8" rx="4" fill="#ececf0"/>
      <circle cx="17" cy="15" r="6" fill="#ff5f57"/>
      <circle cx="37" cy="15" r="6" fill="#febc2e"/>
      <circle cx="57" cy="15" r="6" fill="#28c840"/>
    </g>'''


def build():
    w_anim = animate("width", [(t, fmt(v)) for t, v in win_w])
    h_anim = animate("height", [(t, fmt(v)) for t, v in win_h])

    dock_icons = "".join(
        f'<rect x="{278 + i * 36}" y="453" width="28" height="28" rx="7" fill="{c}"/>'
        for i, c in enumerate(["#5ac8fa", "#34c759", "#ff9f0a", "#ff375f", "#bf5af2", "#64d2ff", "#8e8e93"])
    )

    ripples = "".join(ripple(click, button_center(before, b)) for click, b, before, _, _ in STEPS)
    captions = "".join(caption(click, text) for click, _, _, _, text in STEPS)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif">
  <title>Tilty demo: one click Fill, Left half, Right half, and click again to restore</title>
  <defs>
    <linearGradient id="wall" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#5b8def"/>
      <stop offset="0.55" stop-color="#7b6fd6"/>
      <stop offset="1" stop-color="#e58a9a"/>
    </linearGradient>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="130%">
      <feDropShadow dx="0" dy="6" stdDeviation="8" flood-opacity="0.28"/>
    </filter>
  </defs>

  <!-- Desktop -->
  <rect width="{W}" height="{H}" fill="url(#wall)"/>
  <path d="M0 380 C 160 330, 300 400, 460 350 S 720 320, 800 360 L 800 500 L 0 500 Z" fill="#ffffff" fill-opacity="0.10"/>
  <path d="M0 420 C 200 390, 360 450, 560 410 S 760 400, 800 420 L 800 500 L 0 500 Z" fill="#ffffff" fill-opacity="0.10"/>

  <!-- Menu bar -->
  <rect width="{W}" height="{MENU_H}" fill="#ffffff" fill-opacity="0.55"/>
  <circle cx="18" cy="12" r="5" fill="#1c1c1e" fill-opacity="0.75"/>
  <rect x="34" y="8" width="38" height="8" rx="4" fill="#1c1c1e" fill-opacity="0.55"/>
  <rect x="82" y="8" width="26" height="8" rx="4" fill="#1c1c1e" fill-opacity="0.35"/>
  <rect x="116" y="8" width="26" height="8" rx="4" fill="#1c1c1e" fill-opacity="0.35"/>
  <rect x="150" y="8" width="30" height="8" rx="4" fill="#1c1c1e" fill-opacity="0.35"/>
  <!-- Menu bar extras, with the Tilty icon (rectangle.split.2x1) first -->
  <g fill="none" stroke="#1c1c1e" stroke-opacity="0.85" stroke-width="1.4">
    <rect x="626.7" y="6.7" width="17" height="11" rx="2.5"/>
    <line x1="635.2" y1="7" x2="635.2" y2="17.4"/>
  </g>
  <g fill="#1c1c1e" fill-opacity="0.75">
    <path d="M661 15.5 a1.6 1.6 0 1 0 0.01 0 Z"/>
    <path d="M655.5 12.6 a8 8 0 0 1 11 0 l-1.4 1.4 a6 6 0 0 0 -8.2 0 Z"/>
    <path d="M652.7 9.8 a12 12 0 0 1 16.6 0 l-1.4 1.4 a10 10 0 0 0 -13.8 0 Z"/>
  </g>
  <rect x="680.5" y="7.5" width="20" height="9" rx="2.5" fill="none" stroke="#1c1c1e" stroke-opacity="0.6"/>
  <rect x="682.5" y="9.5" width="13" height="5" rx="1.2" fill="#1c1c1e" fill-opacity="0.75"/>
  <rect x="701.5" y="10.5" width="1.6" height="3" rx="0.8" fill="#1c1c1e" fill-opacity="0.6"/>
  <text x="784" y="16.5" text-anchor="end" font-size="12" font-weight="500" fill="#1c1c1e" fill-opacity="0.85">Fri 11:46</text>

  <!-- Background window -->
  <g transform="translate(470 64)" opacity="0.85" filter="url(#shadow)">
    <rect width="270" height="190" rx="10" fill="#f6f6f8"/>
    <rect width="270" height="28" rx="10" fill="#e4e4e8"/>
    <rect y="18" width="270" height="10" fill="#e4e4e8"/>
    <circle cx="17" cy="14" r="6" fill="#c7c7cc"/>
    <circle cx="37" cy="14" r="6" fill="#c7c7cc"/>
    <circle cx="57" cy="14" r="6" fill="#c7c7cc"/>
  </g>

  <!-- Dock -->
  <rect x="266" y="446" width="268" height="42" rx="12" fill="#ffffff" fill-opacity="0.35" stroke="#ffffff" stroke-opacity="0.4"/>
  {dock_icons}

  <!-- Active window with the Tilty toolbar -->
  <g filter="url(#shadow)">
    {animate_translate(win_pos)}
    {window_contents(w_anim, h_anim)}
    <rect width="{ORIGINAL[2]}" height="{ORIGINAL[3]}" rx="10" fill="none" stroke="#000" stroke-opacity="0.18" stroke-width="0.8">
      {w_anim}
      {h_anim}
    </rect>
    {toolbar()}
  </g>
  {captions}
  {ripples}

  <!-- Cursor -->
  <g>
    {animate_translate(cursor)}
    <path d="M0 0 L0 17 L4.6 13 L7.6 20.2 L10.4 19 L7.4 12 L13 12 Z" fill="#111" stroke="#fff" stroke-width="1.3" stroke-linejoin="round"/>
  </g>
</svg>
'''


if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "docs" / "demo.svg"
    out.parent.mkdir(exist_ok=True)
    out.write_text(build())
    print(f"Wrote {out} ({out.stat().st_size // 1024} KB)")
