"""wt-manager the squirrel — the mascot, as a pure function of what wt-manager found.

Two ideas hold this together.

**The character is an instrument, not a status light.** Its jaw widens with how
much disk you could reclaim, so you read a *magnitude* at a glance and not just
a category. Everything else about it — eyes, colour, the mark it wears — carries
the mood, which is categorical. The swell used to be painted in a pale colour
as well as drawn in the silhouette, and the first thing anyone asked about it
was what the two white squares on the sides of its head were for: a channel
that has to be explained is not a channel.

**Mood is derived, never set.** `mood()` is a pure function of counts, so the
whole truth table is testable without ever drawing a pixel. If the face and the
numbers ever disagree, one of them is a bug, and the function says which.

The art is built from solid masses with the outline *derived* rather than drawn.
Hand-outlining a shape on both sides is how you get a tail that reads as a hollow
ring, which is exactly what the first three drafts of this did.
"""
from __future__ import annotations

from typing import Dict, List, Optional, Tuple

# ── palette ──────────────────────────────────────────────────────────────────
# One letter per pixel. Only '*' takes a live colour: it is the status tint, so
# the mascot and the numbers beside it can never disagree about how bad things are.
# 'b' and 'p' are spare ink: no pixel of the current figure uses them. They
# stay because a skin is a *palette*, not a picture — a second figure that
# wants a pale patch or a blush gets one without every coat having to be
# rewritten, and an unused colour costs a line of JSON.
SLOTS = {
    '#': "outline", 'f': "fur", 's': "fur_dark", 'b': "pale",
    'w': "shine", 'p': "blush", '*': "accent",
}

SKINS: Dict[str, Dict[str, str]] = {
    "acorn":   {"outline": "#1a1614", "fur": "#d6a268", "fur_dark": "#a87646",
                "pale":  "#f7e2c7", "shine": "#fcf8f2", "blush": "#e89696"},
    "ash":     {"outline": "#17181c", "fur": "#9aa3ad", "fur_dark": "#6f7883",
                "pale":  "#e8ecf1", "shine": "#ffffff", "blush": "#c98f8f"},
    "ember":   {"outline": "#1d1210", "fur": "#c8703c", "fur_dark": "#944c26",
                "pale":  "#f6ddc2", "shine": "#fff4e8", "blush": "#e08a7a"},
    "moss":    {"outline": "#141a16", "fur": "#8fa06a", "fur_dark": "#61714a",
                "pale":  "#e9efd8", "shine": "#fbfdf5", "blush": "#d69a86"},
    "midnight":{"outline": "#0c0d12", "fur": "#5a5f7d", "fur_dark": "#3d4159",
                "pale":  "#d8dcea", "shine": "#f2f4fb", "blush": "#b98292"},
}
SKINS.update({
    "cobalt": {"outline": "#101b32", "fur": "#71b7e8", "fur_dark": "#356da8",
               "pale": "#d8efff", "shine": "#f3fbff", "blush": "#9e90e8"},
    "iris":   {"outline": "#21172e", "fur": "#b69be0", "fur_dark": "#715491",
               "pale": "#efe4fb", "shine": "#fffbff", "blush": "#ecafc4"},
    "jade":   {"outline": "#10271f", "fur": "#75c8a2", "fur_dark": "#388967",
               "pale": "#d7f5d9", "shine": "#f4fff2", "blush": "#edbd83"},
})
SKINS.update({
    "graphite": {"outline": "#11131c", "fur": "#91a5ce", "fur_dark": "#536c99",
                 "pale": "#b9dce8", "shine": "#f4fdff", "blush": "#718baf"},
    "sunrise": {"outline": "#322019", "fur": "#fff1d0", "fur_dark": "#a08064",
                "pale": "#fffaf0", "shine": "#ffffff", "blush": "#b9719c"},
    "snow": {"outline": "#332e42", "fur": "#f8f4fa", "fur_dark": "#c9bace",
             "pale": "#ffffff", "shine": "#ffffff", "blush": "#ed9eb6"},
})
SKINS["tropical"] = {"outline": "#183b2c", "fur": "#8dcdbc", "fur_dark": "#a97041",
                     "pale": "#efd49a", "shine": "#fff9e8", "blush": "#e7ad6b"}
SKINS["frost"] = {"outline": "#263c57", "fur": "#f1f8ff", "fur_dark": "#9fc6db",
                  "pale": "#dbeffa", "shine": "#ffffff", "blush": "#ed9349"}
SKINS["chestnut"] = {"outline": "#34221e", "fur": "#c99461", "fur_dark": "#9e6b43",
                     "pale": "#fae5bf", "shine": "#fff6e6", "blush": "#bd7d73"}
DEFAULT_SKIN = "acorn"

# The accent is never in the skin: it is the status tint.
TINTS = {"good": "#3fb27f", "running": "#4a9fd8", "attention": "#e0a33c",
         "bad": "#e0604c", "neutral": "#8b93a1"}


# ── canvas ───────────────────────────────────────────────────────────────────
class _Canvas:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.g = [['.'] * w for _ in range(h)]

    def put(self, x: int, y: int, ch: str) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = ch

    def get(self, x: int, y: int) -> str:
        return self.g[y][x] if 0 <= x < self.w and 0 <= y < self.h else '.'

    def disc(self, cx: float, cy: float, r: float, ch: str) -> None:
        for y in range(self.h):
            for x in range(self.w):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.put(x, y, ch)

    def stroke(self, pts, radii, ch: str) -> None:
        for (cx, cy), r in zip(pts, radii):
            self.disc(cx, cy, r, ch)

    def outline(self, ink: str = '#') -> None:
        """Ring the filled mass from outside. A hollow shape becomes impossible —
        which is what hand-drawing an outline on both sides of a tail produces."""
        solid = set('fsbwp*')
        edge = [(x, y) for y in range(self.h) for x in range(self.w)
                if self.get(x, y) == '.'
                and any(self.get(x + dx, y + dy) in solid
                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        for x, y in edge:
            self.put(x, y, ink)

    def rows(self):
        return ["".join(r) for r in self.g]


# ── the character ────────────────────────────────────────────────────────────
W, H = 22, 23
OX, OY = 3, 7           # where the 16x16 bust sits inside the taller frame

# The eye cell, written outward-in: the left eye takes the string as given and
# the right eye takes it reversed, so one line describes both and a face can
# never be drawn lopsided by a typo. 'f' is fur — the eye simply is not there —
# and 'w' is a single-pixel catchlight.
#
# Two pixels across, not three. A three-wide cell was tried so that `wide` and
# `squint` could afford a catchlight of their own, and it made them worse: at
# this size a third column reads as a bigger *head*, not a bigger eye, and the
# white pixel lands at the outer edge where it looks like a chip out of the
# outline rather than a glint. `wide` keeping its eyes solid is the point of
# `wide` — it is the alarmed face, and the absence of a highlight is what
# makes it read as a stare.
EYES = {
    "open":   ("w#", "##"),   # a round eye, highlight on the outside
    "wide":   ("##", "##"),   # solid: a stare, and no glint in it
    "squint": ("##", "ff"),   # upper lid only: narrowed
    "glance": ("#w", "##"),   # highlight on the inside: looking aside
    "shut":   ("ff", "##"),   # the closed lid, and nothing to catch light
}
BLINK = "shut"

# How far the cheeks bulge, per gauge level: (edge padding, how many of the
# four cheek rows bulge). The gauge is silhouette only - the pouches used to be
# painted in the pale pouch colour and they read as two white squares stuck to
# the sides of the head, which is a thing you ask about rather than a thing you
# read. A jaw that widens is read without being explained.
#
# Padding and row count both move because either alone leaves two levels
# identical: 0 and 1 differ by width, 1 and 2 by width again, 2 and 3 by how
# far down the bulge runs.
POUCH = [(2, 2), (1, 2), (0, 3), (0, 4)]


# ── the cast ─────────────────────────────────────────────────────────────────
# A figure is data, not code. Everything that makes a character a character is
# in these sixteen strings plus four fields; everything that makes it *this*
# app's character — the eyes, the gauge, the wag, the accent — is machinery
# that runs the same over any of them.
#
# The `tell` is the part worth stealing. A figure whose eyes are dark loses the
# status colour entirely at 22 pixels, so every one of these declares at least
# one pixel that is *always* painted in the tint. Without that rule two of
# these four read identically across every mood, which is a mascot that has
# stopped being an instrument and gone back to being a decoration.

BODY = [
    "..#ffffffffff#..",
    ".#ffffffffffff#.",
    "#ffffffffffffff#",
    # Two legs with the gap cut out, not three blocks with seams between them.
    #
    # This was a pale patch until someone asked what the white pixel at the
    # bottom was for — nothing, was the answer — and filling it with fur left
    # the two seams standing, which read as a third leg. A seam only says
    # "these are separate things" when there is background behind it; between
    # two filled blocks it is a line drawn on one thing.
    "#ffff#....#ffff#",
    ".#fff#....#fff#.",
    "..####....####..",
]

# The resting cheek row: what a swell row looks like before the gauge widens it.
REST = ".#ffffffffffff#."


class Part:
    """Rows that move together, and where they sit on each frame.

    Layers rather than one "head", because motion that reads as real is
    *differential*. A tree does not shear — it bends: the crown travels twice
    as far as the middle and the trunk does not move at all. Three layers with
    three amplitudes is the whole of that, and layers compose, so the crown's
    two pixels are the base layer's one plus its own.

    A path shorter than the frame count cycles, which is the cheap way to get
    motion that does not look wound by the same crank: legs on a four-frame
    shuffle under a head on an eight-frame turn drift against each other and
    never repeat the same pairing twice in a row.
    """

    def __init__(self, rows, path):
        self.rows = frozenset(rows)
        self.path = tuple(path)

    def at(self, frame):
        return self.path[frame % len(self.path)]


class Figure:
    """One character. `crown` is rows 0-3, then two eye rows the machinery
    fills, then four cheek rows the gauge widens, then the shared body.

    `eyes` is the top-left of the *left* eye box only; the right one is its
    mirror, so a face can never be drawn lopsided by a typo. `accent` is the
    tell, in (x, y) over the whole 16x16 bust.
    """

    def __init__(self, id, name, tell, crown, accent, eyes=(4, 4),
                 tail="plume", muzzle=(), eye_row="#ffffffffffffff#",
                 parts=(), feet=None, body=None, cheeks=None, poses=()):
        self.id, self.name, self.tell = id, name, tell
        self.crown = list(crown)
        self.body = list(body) if body is not None else BODY
        self.eye_row = eye_row
        self.cheeks = list(cheeks) if cheeks else None
        # Moving layers. See `Part`.
        self.parts = tuple(parts)
        # Hand-authored frame changes: lights, ear folds, hat tips and fronds.
        # These change the drawing rather than translating the whole character.
        self.poses = tuple(poses)
        # Per-frame replacements for the bottom rows. Feet are the one part
        # small enough that redrawing them outright is cheaper than any
        # transform, and a shuffle needs the toes to actually change shape.
        self.feet = [list(f) for f in feet] if feet else None
        self.accent = list(accent)
        self.eyes = eyes
        self.tail = tail
        # Extra pixels stamped after the cheeks, so a muzzle or a beak is not
        # wiped out by the row the gauge rebuilds underneath it.
        self.muzzle = list(muzzle)


FIGURES = {}


def figure(f: Figure) -> Figure:
    FIGURES[f.id] = f
    return f


# The original, and still the default. Ears, a plume, a collar in the tint.
CAT = figure(Figure(
    id="cat", name="Wity", tell="collar",
    crown=["..##........##..",
           ".#ff#......#ff#.",
           ".#fff######fff#.",
           ".#ffffffffffff#."],
    accent=[(7, 6), (8, 6)],
    muzzle=[(7, 7, '#'), (8, 7, '#')],
))

# Claws up, and it never stops fidgeting. The same two mechanics as the
# chicken pointed at different parts: the shear rocks the whole shell instead
# of jerking a head, and the feet are six thin legs that skitter rather than
# two that step. Proof the machinery is general — a crab cost no new code.
CRAB = figure(Figure(
    id="crab", name="Nipper", tell="claws and legs",
    crown=["**............**",
           ".**..........**.",
           "..############..",
           ".#ffffffffffff#."],
    eye_row=".#ffffffffffff#.",
    accent=[(0, 0), (1, 0), (14, 0), (15, 0),
            (1, 1), (2, 1), (13, 1), (14, 1)],
    muzzle=[(6, 7, '#'), (7, 7, '#'), (8, 7, '#'), (9, 7, '#')],
    tail=None,
    parts=[
        # The whole crab scuttles. Shearing the shell off its own legs was
        # the first attempt and it read as a sprite being dragged, because a
        # crab's shell is rigid — what moves is the animal.
        Part(range(0, 16),
             [(0, 0), (1, 0), (1, 0), (0, 0),
              (0, 0), (-1, 0), (-1, 0), (0, 0)]),
        # Claws snap on a four-beat, against the body's eight, so the pairing
        # never lands the same way twice running.
        Part(range(0, 2), [(0, 0), (0, -1), (0, 0), (0, 0)]),
    ],
    feet=[
        ["..############..", "..*..*....*..*..", ".**..**..**..**."],
        ["..############..", "...*..*..*..*...", "..**..**.**..**."],
        ["..############..", "..*..*....*..*..", ".**..**..**..**."],
        ["..############..", ".*..*......*..*.", "**..**....**..**"],
    ],
))

# Three distinct silhouettes, sharing the existing expressions, disk gauge,
# and status accent. Their moving parts leave the feet planted.
# Byte is an original terminal-bot face: a dark visor, ear pods and a smile.
# The rooster's red comb and the rabbit's tall ears remain distinct at 22pt.
ROBOT = figure(Figure(
    id="robot", name="Byte", tell="visor and signal light", tail=None,
    crown=["....########....", "..##ffffffff##..",
           ".#ffffffffffff#.", "#ssffffffffffss#"],
    eye_row="#sffbbbbbbbbffs#",
    accent=[(2, 3), (13, 3), (7, 8), (8, 8)],
    muzzle=[(5, 7, 'b'), (10, 7, 'b'), (6, 8, 'b'), (9, 8, 'b')],
    cheeks=["#sffffffffffffs#", ".#ffffffffffff#.",
            "..#ffffffffff#..", "...##########..."],
    body=["...#ssssssss#...", "..#ssbbbbbbss#..", "..#ssbbbbbbss#..",
          "...#ssssssss#...", "...#ss#..#ss#...", "...####..####..."],
    parts=[Part(range(0, 10), [(0, 0), (0, 0), (1, 0), (1, 0),
                              (0, 0), (0, 0), (-1, 0), (-1, 0)])],
))

ROOSTER = figure(Figure(
    id="rooster", name="Cooper", tell="plum comb and warm beak", tail=None,
    crown=[".....pp.pp......", "....#ppppp#.....",
           "...#ffffffff#...", "..#ffffffffff#.."],
    eye_row="..#fffffffffff#.",
    accent=[(7, 6), (8, 6), (8, 7), (9, 7)],
    muzzle=[(7, 8, 'p'), (8, 8, 'p'), (9, 8, 'p'), (8, 9, 'p')],
    body=[".#fffssssffff#..", "#ffffssssfffff#.", "#fffssssffffff#.",
          ".#fffffffffff#..", "...#ss#.#ss#....", "...****.****...."],
    parts=[Part(range(0, 4), [(0, 0), (0, -1), (0, 0), (0, 0),
                             (1, 0), (0, 0), (0, -1), (0, 0)])],
))

RABBIT = figure(Figure(
    id="rabbit", name="Pip", tell="long ears and tiny paws", tail=None,
    crown=["...##......##...", "..#pf#....#fp#..",
           "..#pf#....#fp#..", "..#fff####fff#.."],
    eye_row=".#ffffffffffff#.",
    accent=[(7, 7), (8, 7)],
    muzzle=[(4, 7, 'p'), (11, 7, 'p'), (7, 8, '#'), (8, 8, '#'),
            (7, 9, 'b'), (8, 9, 'b')],
    body=["..#ffbbbbbbff#..", "..#ffbbbbbbff#..", ".#fffbbbbbbfff#.",
          ".#fff#....#fff#.", ".#fff#....#fff#.", "..####....####.."],
    parts=[Part(range(0, 3), [(0, 0), (0, -1), (0, 0), (0, 0),
                             (1, 0), (0, 0), (-1, 0), (0, 0)])],
))

SNOWMAN = figure(Figure(
    id="snowman", name="Flurry", tell="top hat and carrot nose", tail=None,
    crown=[".....######.....", ".....######.....",
           "...##########...", "...#ffffffff#..."],
    eye_row="..#fffffffffff#.",
    cheeks=["..#fffffffffff#.", "...#ffffffff#...",
            "....#ffffff#....", "...##ffffff##..."],
    accent=[(5, 9), (6, 9), (7, 9), (8, 9), (9, 9), (10, 9)],
    muzzle=[(7, 6, 'p'), (8, 6, 'p'), (9, 6, 'p'), (8, 7, 'p'),
            (6, 8, '#'), (9, 8, '#')],
    body=["..#fffffffffff#.", ".#fffff#fffffff#", ".#fffffffffffff#",
          ".#fffff#fffffff#", "..#fffffffffff#.", "...###########.."],
    parts=[Part(range(0, 4), [(0, 0), (0, -1), (0, 0), (1, 0),
                             (0, 0), (0, -1), (0, 0), (-1, 0)])],
))

PALM = figure(Figure(
    id="palm", name="Coco", tell="swaying fronds and coconuts", tail=None,
    crown=["...fff..fff.....", "..ffffffffff....",
           ".fffffffffffff..", "fff..ffff..ffff."],
    eye_row="....#ssssss#....",
    cheeks=[".....#ssss#.....", ".....#ssss#.....",
            ".....#ssss#.....", ".....#ssss#....."],
    accent=[(2, 2), (3, 2), (12, 2), (13, 2)],
    muzzle=[(3, 4, 'b'), (12, 4, 'b'), (7, 6, '#'), (8, 6, '#')],
    body=[".....#ssss#.....", ".....#ssss#.....", ".....#ssss#.....",
          "....#ssssss#....", "...#bbbbbbbb#...", "..############.."],
    parts=[Part(range(0, 4), [(0, 0), (1, 0), (1, 0), (0, 0),
                             (0, 0), (-1, 0), (-1, 0), (0, 0)])],
))

# Distinct idle actions, with pauses between gestures. The face's expression
# and status accent stay intact; only the named parts are redrawn.
def _shift_row(row, dx):
    return ''.join(row[x - dx] if 0 <= x - dx < len(row) else '.' for x in range(len(row)))


ROBOT.parts = ()
ROBOT.poses = tuple({
    2: ''.join('w' if x in (lamp, lamp + 1) else ch
               for x, ch in enumerate(ROBOT.crown[2])),
    3: ''.join('w' if x in ((0, 1) if i < 4 else (14, 15)) else ch
               for x, ch in enumerate(ROBOT.crown[3]))
} for i, lamp in enumerate((5, 5, 6, 8, 10, 10, 8, 6)))

# Cooper bends the neck forward, pecks twice, then returns to a proud pose.
# The feet and body remain planted, unlike a generic whole-sprite wobble.
ROOSTER.parts = (Part(range(0, 10),
    [(0, 0), (0, 0), (1, 1), (2, 2), (1, 1), (2, 2), (0, 0), (0, 0)]),)

RABBIT.parts = ()
_ears = [RABBIT.crown,
    ["................", ".####.....##....", ".#pff#...#fp#...", "..#fff####fff#.."],
    ["................", "................", ".#ppff####ffpp#.", "..#fff####fff#.."],
    ["................", "...##.....####..", "..#pf#...#ffp#..", "..#fff####fff#.."]]
RABBIT.poses = tuple(dict(enumerate(_ears[i])) for i in (0, 0, 1, 2, 2, 1, 0, 3))

SNOWMAN.parts = ()
_hat = (0, 0, 0, 1, 2, 2, 1, 0)
_arm = (0, 0, 1, 2, 2, 1, 0, 0)
_snow_poses = []
for lean, wave in zip(_hat, _arm):
    pose = {0: _shift_row(SNOWMAN.crown[0], lean * 2),
            1: _shift_row(SNOWMAN.crown[1], lean),
            2: SNOWMAN.crown[2]}
    # Twig hand waves beside the head; the scarf and snowballs stay still.
    for y in range(8, 13):
        row = list((SNOWMAN.cheeks + SNOWMAN.body)[y - 6])
        if y == 11: row[0] = '#'; row[1] = '#'
        if 10 - wave <= y <= 11: row[0] = '#'
        if y == 9 - wave and y >= 8: row[0] = '#'
        pose[y] = ''.join(row)
    # Row 9 carries the scarf; do not overwrite the status channel.
    row = list(pose[9])
    for x, y in SNOWMAN.accent:
        if y == 9: row[x] = '*'
    pose[9] = ''.join(row)
    _snow_poses.append(pose)
SNOWMAN.poses = tuple(_snow_poses)

PALM.parts = ()
_fronds = [PALM.crown,
    ["....fff..fff....", "..ffffffffff....", ".ffffffffff.ff..", "ffff..ff....ffff"],
    [".....ffff.......", "...ffffffffff...", "..fffffffffffff.", "ffff..ff...ffff."],
    ["..fff..fff......", ".fffffffffff....", "ffff.ffffffffff.", "fff...ff..ffff.."]]
PALM.poses = tuple(dict(enumerate(_fronds[i])) for i in (0, 1, 1, 2, 2, 1, 0, 3))

DEFAULT_FIGURE = CAT.id


def bust(cheek: int = 0, eyes: str = "open", fig: Optional[Figure] = None):
    """The character's body: sixteen readable strings, one letter per pixel."""
    fig = fig or CAT
    pad, swell = POUCH[max(0, min(len(POUCH) - 1, cheek))]
    upper, lower = EYES[eyes]
    ex, ey = fig.eyes
    # The mirrored box, so a face cannot go lopsided. Width comes from the
    # cell itself rather than a constant: the two got out of step when the
    # cell was three wide, and the right eye drifted a pixel inboard.
    mx = 16 - ex - len(upper)

    def cheek_row(i: int) -> str:
        """One cheek row. `i` is its index among the four, so only the rows the
        gauge has reached bulge; the rest keep the resting width."""
        if fig.cheeks:
            p = pad
            # Preserve the visor geometry; gauge growth expands its outer edge.
            line = list(fig.cheeks[i])
            if i < swell:
                lo = next((j for j, ch in enumerate(line) if ch != '.'), 3)
                hi = 15 - next((j for j, ch in enumerate(reversed(line)) if ch != '.'), 3)
                if p < lo:
                    line[p] = '#'; line[15-p] = '#'
                    for j in range(p+1, lo+1): line[j] = 'f'
                    for j in range(hi, 15-p): line[j] = 'f'
            return ''.join(line)
        if i >= swell:
            return REST
        p = pad
        return "." * p + "#" + "f" * (16 - 2 * p - 2) + "#" + "." * p

    rows = [list(r) for r in fig.crown]
    for row in (0, 1):
        line = list(fig.eye_row)
        cell = upper if row == 0 else lower
        for dx, ch in enumerate(cell):
            line[ex + dx] = ch
        for dx, ch in enumerate(cell[::-1]):
            line[mx + dx] = ch
        rows.append(line)
    rows += [list(cheek_row(i)) for i in range(4)]
    rows += [list(r) for r in fig.body]

    # Muzzle first, tell last: the tell is the one thing that must survive,
    # because it is the only pixel guaranteed to carry the status colour.
    for x, y, ch in fig.muzzle:
        rows[y][x] = ch
    for x, y in fig.accent:
        rows[y][x] = '*'
    return ["".join(r) for r in rows]

# The tail's root is planted inside the body; only the control point and the
# tip move between frames, so it wags from a fixed base instead of sliding
# around. Two shapes: a plume that tapers to a point, and a beaver's paddle,
# which is the same curve with the taper turned off and a wider brush.
ROOT = (14.0, 14.0)
_WAG4 = [((18.6, 5.0), (10.2, 2.9)),
         ((18.9, 4.0), (10.6, 1.9)),
         ((18.4, 5.4), (9.6, 3.2)),
         ((18.0, 6.2), (9.2, 4.0))]


def _smooth(keys):
    """Every key pose, with a midpoint between each and the next.

    Eight frames rather than four, because four cannot hold. Every motion at
    four frames is a metronome — there is no room for a pose to be *kept* for
    a beat before it changes, and holding is most of what makes a movement
    look like a decision rather than a wobble.
    """
    out = []
    for i, k in enumerate(keys):
        n = keys[(i + 1) % len(keys)]
        out.append(k)
        out.append(tuple(tuple((a + b) / 2 for a, b in zip(pk, pn))
                         for pk, pn in zip(k, n)))
    return out


WAG = _smooth(_WAG4)
FRAMES = len(WAG)            # 8

# A tail carries its own arc as well as its own brush, so a second kind is a
# dict entry rather than a branch. There is one kind at the moment; the shape
# stays because the alternative is the caller knowing what a plume is.
TAILS = {
    "plume": dict(root=ROOT, wag=WAG, base=2.9, taper=0.8),
}

# The motion of last resort: a figure with neither a tail nor any moving part
# bobs, because a still mascot in a window that refreshes itself looks like a
# window that has stopped. Nothing uses it today — both figures move some
# better way — and it stays as the floor under any figure that does not.
BOB = [0, 0, 1, 1]


def _bezier(p0, p1, p2, n: int = 14):
    out = []
    for i in range(n):
        t = i / (n - 1)
        u = 1 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def sprite(cheek: int = 0, eyes: str = "open", frame: int = 0,
           fig: Optional[Figure] = None, tail: bool = True):
    """One frame: the bust, with whatever the figure carries behind its head.

    The tail is drawn first and outlined immediately, then the bust is painted
    over it. That ordering is what puts the tail *behind* the head while its
    arc still reads above it — and it means the tail never needs an internal
    seam.
    """
    fig = fig or CAT
    c = _Canvas(W, H)
    kind = fig.tail if tail else None
    if kind in TAILS:
        spec = TAILS[kind]
        ctrl, tip = spec["wag"][frame % FRAMES]
        pts = _bezier(spec["root"], ctrl, tip)
        radii = [spec["base"] - spec["taper"] * (i / (len(pts) - 1)) ** 2.6
                 for i in range(len(pts))]
        c.stroke(pts, radii, 's')
        c.outline()
    # A figure with a tail sits exactly where it always has. Only a bobbing
    # one is lifted, and only by its own offset — applying the lift to
    # everybody shifted the cat up a pixel, which drove his ears into the
    # plume and left a blank row under his feet. A shared origin is not a
    # place to put one figure's animation.
    still = kind not in TAILS and not fig.parts and not fig.feet and not fig.poses
    # Rows 0-6 of the frame belong to the plume. A figure with no tail was
    # leaving them blank and hanging its own feet off the bottom edge, which
    # at the same drawn height makes it look smaller than the cat as well as
    # cropped. Nothing is up there, so it moves up into it.
    rise = 0
    lift = rise + (1 - BOB[frame % len(BOB)] if still else 0)

    rows = bust(cheek, eyes, fig)
    if fig.poses:
        for y, replacement in fig.poses[frame % len(fig.poses)].items():
            rows[y] = replacement
        # Idle gestures must not erase the live status tint or expression details.
        mutable = [list(row) for row in rows]
        for x, y, ch in fig.muzzle: mutable[y][x] = ch
        for x, y in fig.accent: mutable[y][x] = '*'
        rows = [''.join(row) for row in mutable]
    if fig.feet:
        step = fig.feet[frame % len(fig.feet)]
        rows = rows[:len(rows) - len(step)] + ["".join(r) for r in step]
    for y, row in enumerate(rows):
        dx = dy = 0
        for part in fig.parts:
            if y in part.rows:
                px, py = part.at(frame)
                dx += px
                dy += py
        for x, ch in enumerate(row):
            if ch != '.':
                c.put(OX + x + dx, OY + y + dy - lift, ch)
    c.outline()
    return c.rows()


# ── mood ─────────────────────────────────────────────────────────────────────
# A small glyph beside the head. The third channel: colour, mark and motion all
# carry the mood, so none of them has to survive alone at a small size.
MARKS = {
    "none":  ["....."] * 6,
    "zzz":   [".***.", "....*", "...*.", "..*..", ".***.", "....."],
    "bang":  ["..*..", "..*..", "..*..", "..*..", ".....", "..*.."],
    "query": [".***.", "*...*", "...*.", "..*..", ".....", "..*.."],
    "spark": ["..*..", "*.*.*", ".***.", "*.*.*", "..*..", "....."],
    "scan":  [".....", ".....", "*....", ".....", ".....", "....."],
    "heap":  [".....", ".....", "..*..", ".***.", "*****", "....."],
}

MOODS = {
    #  name        eyes      mark     tint         bob (px per frame)
    "lost":     ("squint", "query", "neutral",   [0]),
    "working":  ("shut",   "scan",  "running",   [0]),
    "alarmed":  ("wide",   "bang",  "bad",       [0, 1]),
    "nudging":  ("glance", "bang",  "attention", [0, 0, 1, 1]),
    "burdened": ("squint", "heap",  "attention", [0, 0, 0, 1]),
    "calm":     ("open",   "none",  "running",   [0, 0, 1, 1]),
    "proud":    ("open",   "spark", "good",      [0, 0, 1, 1]),
    "asleep":   ("shut",   "zzz",   "good",      [0, 0, 0, 1, 1, 1]),
}

MEANING = {
    "lost":     "something here cannot be trusted",
    "working":  "counting",
    "alarmed":  "your move, and it is specific",
    "nudging":  "you forgot something",
    "burdened": "carrying a lot of dead weight",
    "calm":     "work in flight, nothing urgent",
    "proud":    "nothing waiting, nothing wasted",
    "asleep":   "nothing in flight",
}

# Reclaimable disk, in KB, at which each swell level starts.
GAUGE_KB = [0, 1 << 20, 10 << 20, 50 << 20]      # 0, 1G, 10G, 50G


def gauge(reclaim_kb: int) -> int:
    """How far the jaw widens. Absolute, not a ratio — a machine holding
    100G of rebuildable output is hoarding whether or not that is 9% or 99% of
    the total, and the ratio would let a huge repo hide behind its own size."""
    level = 0
    for i, floor in enumerate(GAUGE_KB):
        if reclaim_kb >= floor:
            level = i
    return level


# How much of what you are looking at has to be unreadable before the whole
# view stops being worth trusting. Firing on the *presence* of one unreadable
# repo is the same mistake as calling a branch blocked for a check that fails
# repo-wide: a signal that trips this easily stops discriminating, and here it
# would bury a genuinely blocked PR behind a shrug.
UNTRUSTED_SHARE = 0.5


def mood(blocked: int = 0, review: int = 0, stale: int = 0, active: int = 0,
         waiting: int = 0, reclaim_kb: int = 0, scanning: bool = False,
         untrusted_share: float = 0.0, draft: int = 0) -> str:
    """What wt-manager found, as one face. Pure, so the truth table is testable.

    The order is the argument, not an implementation detail:

    * being untrusted wins, but only once *most* of the view is affected. If
      the forge could not be read for half of what you are looking at, every
      number is a guess and a confident face over guessed numbers is worse than
      no face. For one repo out of twenty-seven it is not, and saying so would
      hide the blocked PR in the nineteen that read fine.
    * `working` beats everything derived, because "I am still counting" is the
      more useful answer to "is this still true".
    * `alarmed` beats `nudging`: something blocking you now outranks something
      you forgot a month ago.
    * `burdened` sits *below* both, because dead weight is never urgent — it is
      the thing you notice once nothing else is shouting. Putting it higher
      would make the mascot nag about disk while a PR sits blocked.
    """
    if untrusted_share >= UNTRUSTED_SHARE:
        return "lost"
    if scanning:
        return "working"
    if blocked or review:
        return "alarmed"
    if stale:
        return "nudging"
    if gauge(reclaim_kb) >= 2:
        return "burdened"
    # A draft is yours and not yet offered - work in flight, as much as an
    # active branch is. Five open drafts used to read "nothing in flight".
    if active or waiting or draft:
        return "calm"
    return "proud" if reclaim_kb == 0 else "asleep"


def human(kb: int) -> str:
    """A size, spelled far enough to be read as one.

    The third copy of this function — the engine formats the table, the app
    formats the window, and this one formats the sentences the mascot carries.
    The duplication is deliberate: `mascot` is imported by the engine and not
    the other way round, and the app cannot import Python at all. What is not
    optional is that they agree, because the same number appears in all three
    within one screen.
    """
    if kb is None or kb < 0:
        return "—"
    for suffix, factor in (("TB", 1 << 30), ("GB", 1 << 20), ("MB", 1 << 10)):
        if kb >= factor:
            v = kb / factor
            return f"{v:.1f}{suffix}" if v < 10 else f"{v:.0f}{suffix}"
    return f"{kb}KB"


def headline(mood_name: str, counts: Dict[str, int], reclaim_kb: int, worktrees: int) -> str:
    """The state, in a handful of words. One line; it must never wrap.

    Derived from the *mood*, not from a second ladder of its own: two rankings
    of one set of facts drift, so every surface that shows a sentence shows
    this one. It is a summary and nothing else - the facts it used to cram
    into a run-on sentence ("...but 18 pieces of work have been forgotten, and
    you are carrying 244G...") are `insights`, one tag each, so the headline
    stays the same length however bad the machine is.
    """
    if not worktrees:
        return "No worktrees found here"
    if mood_name == "lost":
        return "Some of this could not be read"
    if mood_name == "working":
        return "Counting\u2026"
    if mood_name == "alarmed":
        n = counts.get("blocked", 0) + counts.get("review", 0)
        return "One thing needs you" if n == 1 else f"{n} things need you"
    if mood_name in ("nudging", "burdened"):
        return "Nothing is blocking you"
    if mood_name == "calm":
        mine = counts.get("active", 0) + counts.get("draft", 0)
        return "Nothing is on you" if counts.get("waiting", 0) and not mine \
            else "Work in flight, nothing urgent"
    if mood_name == "proud":
        return "Nothing waiting, nothing wasted"
    return "Nothing in flight"


# Each insight is one fact, carried once: never also in the headline, never
# also in the inventory strip. `tint` names a palette idea, `target` the
# section that answers it, so a tag is navigation rather than decoration.
#
# `solo` says whether this surface is the fact's only home. Most of these tags
# restate a number the app already shows somewhere permanent - the count beside
# a sidebar section, or the headline itself - and a surface that has one of
# those should not print the number twice. Eight tags of equal weight wrapping
# onto two rows is what "show everything" looks like, and five of the eight
# were already on screen six inches to the left. Only two facts here have
# nowhere else to live: work that exists on this machine alone, and repos that
# could not be read. A surface with no sidebar (the page) shows them all.
def insights(counts: Dict[str, int], reclaim_kb: int, unpushed: int,
             finished: int = 0, unreadable: int = 0) -> List[Dict[str, object]]:
    def n(k):
        return counts.get(k, 0)
    out: List[Dict[str, object]] = []
    need = n("blocked") + n("review")
    if need:
        out.append({"id": "need", "label": f"{need} need{'s' if need == 1 else ''} you",
                    "tint": "blocked", "target": "need", "value": need,
                    "solo": False})
    if n("stale"):
        out.append({"id": "stale", "label": f"{n('stale')} forgotten",
                    "tint": "stale", "target": "forgot", "value": n("stale"),
                    "solo": False})
    if unpushed:
        out.append({"id": "unpushed",
                    "label": f"{unpushed} commit{'s' if unpushed != 1 else ''} only here",
                    "tint": "risk", "target": "overview", "value": unpushed,
                    "solo": True})
    if reclaim_kb > 0:
        out.append({"id": "reclaim", "label": f"{human(reclaim_kb)} rebuildable",
                    "tint": "reclaim", "target": "disk", "value": reclaim_kb,
                    "solo": False})
    if n("waiting"):
        out.append({"id": "waiting", "label": f"{n('waiting')} with others",
                    "tint": "waiting", "target": "others", "value": n("waiting"),
                    "solo": False})
    if n("draft"):
        out.append({"id": "draft", "label": f"{n('draft')} draft{'s' if n('draft') != 1 else ''}",
                    "tint": "draft", "target": "flight", "value": n("draft"),
                    "solo": False})
    if finished:
        out.append({"id": "finished", "label": f"{finished} finished",
                    "tint": "merged", "target": "done", "value": finished,
                    "solo": False})
    if unreadable:
        out.append({"id": "unreadable",
                    "label": f"{unreadable} repo{'s' if unreadable != 1 else ''} unreadable",
                    "tint": "neutral", "target": "overview", "value": unreadable,
                    "solo": True})
    return out


def face(reclaim_kb: int = 0, figure: str = DEFAULT_FIGURE, **counts) -> dict:
    """Everything a renderer needs: art, colour, motion, and why."""
    fig = FIGURES.get(figure, CAT)
    m = mood(reclaim_kb=reclaim_kb, **counts)
    eyes, mark, tint, bob = MOODS[m]
    level = gauge(reclaim_kb)
    return {
        "mood": m, "meaning": MEANING[m], "eyes": eyes, "mark": mark,
        "mark_rows": MARKS[mark], "tint": TINTS[tint], "tint_name": tint,
        "bob": bob, "gauge": level, "figure": fig.id,
        "sprite": sprite(level, eyes, 0, fig),
        # every wag frame, so a renderer can animate without knowing the geometry
        "frames": [sprite(level, eyes, i, fig) for i in range(FRAMES)],
        "width": W, "height": H,
    }


# ── export ───────────────────────────────────────────────────────────────────
def export() -> dict:
    """Every frame the character can ever be in, as data.

    The app that draws this does not reimplement any of it. One source of truth
    for the art, for the same reason the headline is derived from the mood: two
    implementations of one rule diverge on the first case neither author thought
    about, and here the divergence would be a mascot that disagrees with itself
    between the menu bar and the page.
    """
    from companion_art import export as export_companions
    sprites = {}
    for fig in FIGURES.values():
        for gauge_level in range(len(POUCH)):
            for eye in EYES:
                for frame in range(FRAMES):
                    sprites[f"{fig.id}/{gauge_level}/{eye}/{frame}"] = \
                        sprite(gauge_level, eye, frame, fig)
    return {
        "version": 1, "width": W, "height": H, "frames": FRAMES,
        "slots": SLOTS, "skins": SKINS, "tints": TINTS,
        "companion": export_companions(SKINS, SLOTS, EYES, FRAMES),
        "default_skin": DEFAULT_SKIN,
        # The cast, so the picker is data too: a fifth character is a dozen
        # strings here and nothing at all in the app.
        "figures": [{"id": f.id, "name": f.name, "tell": f.tell}
                    for f in FIGURES.values()],
        "default_figure": DEFAULT_FIGURE,
        "gauge_kb": GAUGE_KB,
        "moods": {name: {"eyes": e, "mark": m, "tint": t, "bob": b,
                         "meaning": MEANING[name]}
                  for name, (e, m, t, b) in MOODS.items()},
        "marks": MARKS,
        "sprites": sprites,
    }


if __name__ == "__main__":
    import json as _json
    import sys as _sys
    out = _sys.argv[1] if len(_sys.argv) > 1 else "-"
    blob = _json.dumps(export(), separators=(",", ":"))
    if out == "-":
        print(blob)
    else:
        with open(out, "w") as fh:
            fh.write(blob)
        print(f"{len(blob)} bytes -> {out}")
