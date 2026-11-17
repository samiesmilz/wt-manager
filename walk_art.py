"""Walking frames drawn from each character's own front portrait.

A walker keeps its portrait's head, features and coat: the face turns toward
the direction of travel, the far side falls into shade, and the legs are
redrawn at the portrait's thickness. One step is eight poses, played twice in
the sixteen-frame cycle: a planted foot slides back one art pixel per pose,
which is exactly how far the window travels, so it holds still on screen.

Standard library only. `sprite(figure, eyes, frame)` is passed in, so this
module never imports the art it redraws.
"""
S = 32
FLOOR = 31
REDRAWN = ('robot', 'rooster', 'rabbit', 'snowman', 'orb', 'antenna', 'pup', 'rex')
_sprite = None

def front(fig, eyes='open'):
    return [list(r) for r in _sprite(fig, eyes, 0)]
def blank(): return [['.'] * S for _ in range(S)]
def mirror(g): return [r[::-1] for r in g]

class C:
    def __init__(s): s.g = [['.'] * S for _ in range(S)]
    def px(s, x, y, ch):
        if 0 <= x < S and 0 <= y < S: s.g[y][x] = ch
    def rect(s, x0, y0, x1, y1, ch):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1): s.px(x, y, ch)
    def box(s, x0, y0, x1, y1, ch):          # outlined rectangle
        s.rect(x0, y0, x1, y1, '#'); s.rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, ch)
    def rbox(s, x0, y0, x1, y1, ch, r=1):    # outlined, corners cut
        s.box(x0, y0, x1, y1, ch)
        for (cx, cy, dx, dy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
            for i in range(r):
                for j in range(r - i):
                    s.px(cx + dx * i, cy + dy * j, '.')
            for i in range(r + 1):
                s.px(cx + dx * i, cy + dy * (r - i), '#')
    def blob(s, rows, ch):                    # rows: (y, x0, x1) spans, outlined after
        cells = set()
        for y, x0, x1 in rows:
            for x in range(x0, x1 + 1): cells.add((x, y))
        for (x, y) in cells:
            edge = any((x + dx, y + dy) not in cells for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            s.px(x, y, '#' if edge else ch)
    def rows(s): return [''.join(r) for r in s.g]

# stance 5 poses sliding back 1px each, swing 3 poses
FOOT_X = (2, 1, 0, -1, -2, -1, 0, 1)
FOOT_UP = (0, 0, 0, 0, 0, 1, 2, 1)
BOB = (0, 0, -1, 0, 0, 0, -1, 0)
def planted(frame): return 'near' if frame % 8 < 4 else 'far'

def limb(c, hipx, hipy, footx, footy, w, ch):
    """A leg from hip to ankle, w inner pixels wide, outlined both sides."""
    n = max(1, footy - hipy)
    for i in range(n + 1):
        x = round(hipx + (footx - hipx) * i / n); y = hipy + i
        c.px(x - 1, y, '#'); c.rect(x, y, x + w - 1, y, ch); c.px(x + w, y, '#')

# ───────────── Byte ─────────────
def byte(view='walk', frame=0, eyes='open'):
    """view: 'front' | 'turn' | 'walk' (three-quarter, facing right)."""
    c = C(); f = frame % 8
    walking = view == 'walk'
    t = {'front': 0, 'turn': 1, 'walk': 2, 'stand': 2}[view]
    bob = BOB[f] if walking else 0
    side = (0, 2, 4)[t]                       # width of the receding side panel
    # legs
    def leg(hip, phase, ch):
        fx = hip + (FOOT_X[phase] if walking else 0); up = FOOT_UP[phase] if walking else 0
        limb(c, hip, 25 + bob, fx, 28 - up, 3, 's')
        c.box(fx - 2 + (1 if t else 0), 29 - up, fx + 4 + (1 if t else 0), 31 - up, ch)
    hips = ((11, 19), (12, 18), (11, 17))[t]
    leg(hips[1], (f + 4) % 8, 's' if t else 'f')     # far leg, darker when turned
    leg(hips[0], f, 'f')
    # far arm
    sw = (1, 1, 0, -1, -1, -1, 0, 1)[f] if walking else 0
    if t == 0: c.box(25, 19 , 28, 25, 's')
    else: c.box(22 - sw, 20 + bob, 25 - sw, 25 + bob, 's')
    # body
    bx0, bx1 = ((6, 26), (8, 25), (9, 23))[t]
    if t == 0: bx0, bx1 = 8, 24
    c.box(bx0, 19 + bob, bx1, 25 + bob, 'f')
    if side: c.rect(bx0 + 1, 20 + bob, bx0 + side - 1, 24 + bob, 's')
    px0 = bx0 + side + 2
    c.rect(px0, 20 + bob, bx1 - 3, 22 + bob, 'h'); c.rect(px0 + 1, 20 + bob, bx1 - 4, 20 + bob, 'l')
    c.px(bx1 - 2, 23 + bob, 'w')
    # near arm
    if t == 0: c.box(4, 19, 7, 25, 's')
    else: c.box(7 + sw, 20 + bob, 10 + sw, 26 + bob, 's'); c.px(8 + sw, 21 + bob, 'f')
    # head
    hx0, hx1 = ((6, 26), (6, 26), (6, 26))[t]
    hy0, hy1 = 5 + bob, 18 + bob
    c.box(hx0, hy0, hx1, hy1, 'f')
    if side:
        c.rect(hx0 + 1, hy0 + 1, hx0 + side, hy1 - 1, 's'); c.rect(hx0 + side + 1, hy0, hx0 + side + 1, hy1, '#')
    fx0 = hx0 + (side + 2 if side else 1)
    c.rect(fx0, hy0 + 1, fx0 + 4, hy0 + 1, 'w')
    c.rect(fx0, hy0 + 4, hx1 - 1, hy0 + 10, 'h'); c.rect(fx0 + 1, hy0 + 5, hx1 - 2, hy0 + 9, 'v')
    c.rect(fx0, hy1 - 1, hx1 - 1, hy1 - 1, 's'); c.rect(fx0 + 5, hy1 - 1, fx0 + 5, hy1 - 1, 'l')
    def eye(x, w):
        if eyes == 'shut': c.rect(x, hy0 + 7, x + w - 1, hy0 + 7, '#'); return
        if eyes == 'squint': c.rect(x, hy0 + 6, x + w - 1, hy0 + 7, '#'); return
        top = hy0 + (4 if eyes == 'wide' else 5)
        c.rect(x, top, x + w - 1, hy0 + 8, '#')
        c.px(x + w - 1 if eyes == 'glance' else x, top, 'w')
    if t == 0: eye(11, 3); eye(19, 3)
    elif t == 1: eye(13, 3); eye(20, 3)
    else: eye(15, 3); eye(22, 2)
    # ear pods
    if t == 0: c.box(3, 10, 6, 14, 'v'); c.box(26, 10, 29, 14, 'v')
    elif t == 1: c.box(4, 10, 7, 14, 'v'); c.box(26, 10, 28, 14, 'v')
    else: c.box(6, 9, 10, 14, 'v')
    # antenna
    ax = (15, 16, 17)[t]
    c.rect(ax, hy0 - 1, ax, hy0 - 1, '#')
    c.rbox(ax - 2, hy0 - 5, ax + 2, hy0 - 2, 'l')
    return c.rows()


def shift_box(g, box, dx):
    """Slide the features in a box toward the facing side; the vacated columns
    repeat the box's own left edge, so any fill or shading carries across."""
    x0, y0, x1, y1 = box
    for y in range(y0, y1 + 1):
        row = g[y][x0:x1 + 1]
        g[y][x0:x1 + 1] = [row[0]] * dx + row[:len(row) - dx]

def shade_far(g, y0, y1, width=2, lit='f', dark='s'):
    """Darken the far (left) edge of the body so the turn reads as depth."""
    for y in range(y0, y1 + 1):
        xs = [x for x in range(S) if g[y][x] != '.']
        if not xs: continue
        n = 0
        for x in range(xs[0], S):
            if g[y][x] == lit:
                g[y][x] = dark; n += 1
                if n >= width: break
            elif g[y][x] not in ('#', dark): break

def lift(g, top, bottom, dy):
    """Move rows top..bottom up by dy (dy > 0), leaving the rows below clear."""
    if dy <= 0: return
    for y in range(top, bottom + 1):
        if y - dy >= 0: g[y - dy] = g[y][:]
    for y in range(bottom - dy + 1, bottom + 1): g[y] = ['.'] * S

def px(g, x, y, ch):
    if 0 <= x < S and 0 <= y < S: g[y][x] = ch

def leg(g, hip, top, footx, up, w, ch, foot, outline=True):
    """A leg of inner width w from (hip, top) to the foot, and the foot itself.
    foot = (width, height, char, forward): the box sits on the floor, minus `up`."""
    fw, fh, fch, fwd = foot
    ankle = 31 - up - fh
    n = max(1, ankle - top)
    for i in range(n + 1):
        x = round(hip + (footx - hip) * i / n); y = top + i
        if outline: px(g, x - 1, y, '#'); px(g, x + w, y, '#')
        for k in range(w): px(g, x + k, y, ch)
    fx0 = footx - (fw - w) // 2 + fwd
    for y in range(31 - up - fh + 1, 32 - up):
        for x in range(fx0, fx0 + fw):
            edge = outline and fch != '#' and (x in (fx0, fx0 + fw - 1) or y in (31 - up - fh + 1, 31 - up))
            px(g, x, y, '#' if edge else fch)

# ── biped walkers taken from their portraits ────────────────────────────────
BIPED = {
    # legtop: first row of legs · hips (near, far) · w: inner leg width · foot (w, h, char, forward)
    'antenna': dict(legtop=27, hips=(12, 18), w=3, ch='f', far='s', foot=(5, 1, 's', 1), face=(8, 12, 24, 18), shade=(8, 24), close=(10, 23)),
    'pup':     dict(legtop=27, hips=(12, 17), w=3, ch='f', far='s', foot=(7, 2, '#', 1), face=(9, 9, 22, 17), shade=(21, 25), close=(9, 23)),
    'rex':     dict(legtop=25, hips=(11, 17), w=4, ch='f', far='s', foot=(7, 3, '#', 1), face=(6, 6, 26, 14), shade=(17, 23), close=(8, 24)),
}
def biped(fig, frame, eyes='open', stand=False):
    c = BIPED[fig]; f = frame % 8
    g = front(fig, eyes)
    for y in range(c['legtop'], S): g[y] = ['.'] * S
    x0, x1 = c['close']
    for x in range(x0, x1 + 1): px(g, x, c['legtop'] - 1, '#')
    shift_box(g, c['face'], 2)
    shade_far(g, *c['shade'])
    bob = 0 if stand else -BOB[f]
    lift(g, 0, c['legtop'] - 1, bob)
    out = blank()
    near, far = c['hips']
    for hip, ph, ch in ((far, (f + 4) % 8, c['far']), (near, f, c['ch'])):
        fx = hip + (0 if stand else FOOT_X[ph]); up = 0 if stand else FOOT_UP[ph]
        leg(out, hip, c['legtop'] - 1 - bob, fx, up, c['w'], ch, c['foot'])
    for y in range(S):
        for x in range(S):
            if g[y][x] != '.': out[y][x] = g[y][x]
    return [''.join(r) for r in out]

# ── Cooper: the portrait is already a profile, facing left ──────────────────
def rooster(frame, eyes='open', stand=False):
    f = frame % 8
    g = mirror(front('rooster', eyes))
    for y in range(25, S): g[y] = ['.'] * S
    for x in range(9, 20): px(g, x, 24, '#' if g[24][x] == '.' else g[24][x])
    bob = 0 if stand else -BOB[f]
    nod = 0 if stand else (0, 0, 1, 1, 0, 0, 1, 1)[f]         # head leads each step
    if nod:
        for y in range(0, 17):
            row = g[y][14:32]; g[y][14:32] = ['.'] + row[:-1]
    lift(g, 0, 24, bob)
    out = blank()
    for hip, ph, ch in ((11, (f + 4) % 8, 't'), (17, f, 'a')):
        fx = hip + (0 if stand else FOOT_X[ph]); up = 0 if stand else FOOT_UP[ph] * 2
        leg(out, hip, 24 - bob, fx, up, 1, ch, (5, 1, ch, 1), outline=False)
    for y in range(S):
        for x in range(S):
            if g[y][x] != '.': out[y][x] = g[y][x]
    return [''.join(r) for r in out]

# ── Pip: a hop, both feet together ──────────────────────────────────────────
HOP_UP = (0, 0, 0, 0, 0, 2, 3, 2)
def rabbit(frame, eyes='open', stand=False):
    f = frame % 8
    g = front('rabbit', eyes)
    for y in range(28, S): g[y] = ['.'] * S
    for x in range(11, 22): px(g, x, 27, g[27][x] if g[27][x] != '.' else '#')
    for x in range(12, 21): px(g, x, 28, '#')
    shift_box(g, (6, 13, 26, 23), 2)
    shade_far(g, 13, 25)
    up = 0 if stand else HOP_UP[f]
    squash = 0 if stand else (1 if f == 0 else 0)             # lands low
    lift(g, 0, 28, up)
    if squash:
        g2 = blank()
        for y in range(0, 29): g2[min(S - 1, y + 1)] = g[y][:]
        g = g2
    out = blank()
    for hip, ch in ((19, 's'), (10, 'f')):
        fx = hip + (0 if stand else FOOT_X[f]); fu = up
        x0 = fx - 3
        for y in range(28 - fu, 32 - fu):
            for x in range(x0, x0 + 8):
                edge = x in (x0, x0 + 7) or y in (28 - fu, 31 - fu)
                px(out, x, y, '#' if edge else ch)
    for y in range(S):
        for x in range(S):
            if g[y][x] != '.': out[y][x] = g[y][x]
    return [''.join(r) for r in out]

# ── Flurry: no legs. A waddle: the upper snowball rocks, the base stays down ─
def snowman(frame, eyes='open', stand=False):
    f = frame % 8
    g = front('snowman', eyes)
    shift_box(g, (9, 11, 22, 17), 2)
    if stand: return [''.join(r) for r in g]
    rock = (0, 1, 1, 0, 0, -1, -1, 0)[f]
    out = blank()
    for y in range(S):
        dx = rock if y <= 20 else 0                          # hat, head and scarf lean
        for x in range(S):
            if g[y][x] != '.': px(out, x + dx, y, g[y][x])
    # a little snow kicked back, drifting up and away over two poses
    if f == 1: px(out, 5, 31, 'w')
    if f == 2: px(out, 4, 30, 'w'); px(out, 3, 31, 'w')
    if f == 5: px(out, 4, 31, 'w')
    if f == 6: px(out, 3, 29, 'w'); px(out, 4, 31, 'w')
    return [''.join(r) for r in out]

# ── Mallow: rolls. The face leans into the roll; a seam travels round the rim ─
def orb(frame, eyes='open', stand=False):
    f = frame % 8
    g = front('orb', eyes)
    shift_box(g, (9, 11, 25, 20), 1)
    if stand: return [''.join(r) for r in g]
    out = blank()
    up = 0                                                   # a ball stays on the floor
    for y in range(S):
        for x in range(S):
            if g[y][x] != '.': px(out, x, y, g[y][x])
    # the rolling seam: a short shadow that crosses the lower half, front to back
    sx = 23 - f * 2
    for k in range(3):
        y = 26 - up - abs(sx + k - 15) // 4
        if out[y][sx + k] in ('f', 'b'): out[y][sx + k] = 's'
    return [''.join(r) for r in out]


# ── Bork, on four legs: his own head, ears and bandana on a dog's body ──────
def pup4(frame, eyes='open', stand=False):
    f = frame % 8
    src = front('pup', eyes)
    shift_box(src, (9, 9, 22, 17), 2)                         # face turns toward travel
    bob = 0 if stand else -BOB[f]
    wag = 0 if stand else (0, 1, 1, 0, 0, -1, -1, 0)[f]
    c = C()
    # tail, up and wagging
    c.box(2 + wag, 10 - bob, 5 + wag, 14 - bob, 'f'); c.box(3, 13 - bob, 6, 18 - bob, 'f'); c.rect(4, 14 - bob, 5, 17 - bob, 'f')
    def leg(hip, ph, ch):
        fx = hip + (0 if stand else FOOT_X[ph]); up = 0 if stand else FOOT_UP[ph]
        limb(c, hip, 24 - bob, fx, 29 - up, 3, ch)
        c.rect(fx - 1, 30 - up, fx + 4, 31 - up, '#')
    leg(8, (f + 4) % 8, 's'); leg(18, f, 's')                # far pair, in shadow
    c.box(3, 16 - bob, 22, 25 - bob, 'f')                    # body
    c.rect(7, 22 - bob, 18, 24 - bob, 's')                   # belly, as in the portrait
    leg(5, f, 'f'); leg(15, (f + 4) % 8, 'f')                # near pair
    hx, hy = 14, 3 - bob                                     # head: the portrait's own pixels
    g = c.g
    for y in range(8, 19):                                   # far ear, a sliver behind the head
        for x in range(26, 28):
            if src[y][x + 1] != '.': px(g, hx + 16 + (x - 26), hy + y - 4, src[y][x + 1])
    c.rect(hx + 1, hy + 14, hx + 13, hy + 16, 'r'); c.rect(hx, hy + 14, hx, hy + 16, '#')   # bandana
    c.rect(hx + 1, hy + 17, hx + 13, hy + 17, '#'); c.rect(hx - 2, hy + 15, hx - 1, hy + 17, 'r'); c.px(hx - 3, hy + 16, '#')
    for y in range(4, 18):
        for x in range(8, 24):
            if src[y][x] != '.': px(g, hx + x - 8, hy + y - 4, src[y][x])
    for y in range(8, 19):                                   # near ear, hanging in front
        for x in range(3, 9):
            if src[y][x] != '.': px(g, hx - 3 + x - 3, hy + y - 4, src[y][x])
    return c.rows()



def planted_feet(frame):
    """Which side bears weight on this pose: the near foot for poses 0-3."""
    return 'near' if frame % 8 < 4 else 'far'

def walking(figure, eyes, frame, sprite):
    """Rows of the right-facing walking frame; the renderer mirrors for left."""
    global _sprite
    _sprite = sprite
    f = frame % 8
    if figure == 'robot': return byte('walk', f, eyes)
    if figure == 'rooster': return rooster(f, eyes)
    if figure == 'rabbit': return rabbit(f, eyes)
    if figure == 'snowman': return snowman(f, eyes)
    if figure == 'orb': return orb(f, eyes)
    if figure == 'pup': return pup4(f, eyes)
    if figure in BIPED: return biped(figure, f, eyes)
    raise ValueError(figure)


# ── Wity and Nipper, on their own 22x23 grid ────────────────────────────────
# Their portraits are the original small sprites, and the app draws them at a
# larger pixel, so they keep that grid. The method is the same: the walk is
# the portrait itself, with the face turned and the feet redrawn.
OW, OH = 22, 23

def _set(g, x, y, ch):
    if 0 <= x < OW and 0 <= y < OH: g[y][x] = ch

def original(figure, eyes, frame, rows):
    """`rows` is the figure's own front portrait for this expression."""
    f = frame % 8
    # The portrait's accent slot is tinted live by the app; the companion
    # palettes have no such slot, so it takes a fixed colour that is in them.
    accent = 'p' if figure == 'cat' else 'a'
    g = [[accent if ch == '*' else ch for ch in r] for r in rows]
    for y in (21, 22): g[y] = ['.'] * OW
    if figure == 'cat':
        shift_box(g, (5, 10, 16, 14), 1)                    # the face turns
        sway = (0, 0, 1, 1, 0, 0, -1, -1)[f]                 # the plume follows
        if sway:
            for y in range(0, 6):
                row = g[y]
                g[y] = (['.'] + row[:-1]) if sway > 0 else (row[1:] + ['.'])
        for hip, ph in ((13, (f + 4) % 8), (4, f)):          # far foot, then near
            x = hip + FOOT_X[ph]; up = FOOT_UP[ph]
            for k, ch in enumerate('#fff#'): _set(g, x + k, 21 - up, ch)
            for k in range(1, 5): _set(g, x + k, 22 - up, '#')
            if up:                                            # the leg reaches down to it
                for k in range(1, 4): _set(g, x + k, 20, 'f')
        return [''.join(r) for r in g]
    if figure == 'crab':
        snap = (0, 0, 0, 1, 1, 0, 0, 0)[f]
        if snap:                                              # claws open a pixel
            for x in (3, 4, 17, 18): _set(g, x, 5, '#')
        for i, hip in enumerate((5, 8, 13, 16)):
            ph = f if i % 2 == 0 else (f + 4) % 8
            x = hip + FOOT_X[ph]; up = FOOT_UP[ph]
            _set(g, x - 1, 21 - up, '#'); _set(g, x, 21 - up, accent); _set(g, x + 1, 21 - up, '#')
            _set(g, x - 1, 22 - up, accent); _set(g, x, 22 - up, accent)
        return [''.join(r) for r in g]
    raise ValueError(figure)
