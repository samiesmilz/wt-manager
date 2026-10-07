# Mascot design rules

Characters express personality; the framed badge communicates engine status.
Changing a character or coat must not change the strength or meaning of that signal.

- Use the same nine-pixel badge, borders and mood glyphs for every character, including custom pictures. Take the live tint and mood from the engine.
- Keep the status badge nine points on every floating character, including Wity and custom pictures.
- Use a simple right-pointing arrow for attention; avoid cross-shaped status symbols.
- Keep all eight moods distinguishable without colour. Two contrasting borders isolate the badge from coats and light/dark backgrounds.
- For the menu bar, use the shared 22×23 source grid and bottom baseline. Resting figures occupy at least 16 rows; intentional pecks may compress during motion.
- Draw the seven new floating characters separately on a 32×32 grid. Render at integral 2× scale (64×64pt) inside the existing 84×84pt movable window. Never enlarge menu-bar art as a substitute for detail. Keep a nine-point badge so it does not obscure the character.
- Give each character its own gesture: scanning lights, double peck, folding ears, scarf/twig wave and bending fronds. Avoid applying one whole-sprite bob to the cast.
- Keep eyes unobstructed in every frame. Coco's coconuts must sit outside the eye cells.
- Prefer coat colours that do not impersonate warning or success colours. The separate badge remains the status authority.

## Verify a change

Run the Python and Swift suites, then render from the packaged app so its resources are present:

```sh
python3 -m unittest
cd app && swift test && cd ..
make bundle
app/wt-manager.app/Contents/MacOS/wt-manager --snapshot-signals /tmp/wt-signals
app/wt-manager.app/Contents/MacOS/wt-manager --snapshot-cast /tmp/wt-cast
app/wt-manager.app/Contents/MacOS/wt-manager --snapshot-motion /tmp/wt-motion
app/wt-manager.app/Contents/MacOS/wt-manager --snapshot-merge /tmp/wt-merge
```

Inspect light and dark images at their real size. Raster tests cover badge consistency across every character, mood and coat; other tests check glyph uniqueness, contrast, baselines and distinct alarm expressions. These checks establish consistency, not artistic quality or complete accessibility coverage. Live desktop movement and assistive-technology behaviour still need device testing.

Mallow keeps the reference’s limbless orb silhouette and diagonal eyes. Bop keeps separate side arms, antennae and short feet. Do not turn these into another shared humanoid body. Mallow rolls its highlight; Bop flexes antennae and waves one arm.

## Direct controls

- Primary desktop and menu-bar clicks open the window immediately; secondary clicks expose maintenance actions. Dragging never opens the window.
- Keep every character portrait visible above scrolling content. One click selects that character and highlights it; the header portrait cycles characters.
- PR counters reveal matching, deduplicated PR links. Open PRs are visible by default, with title/branch fallback and explicit feedback when a link is unavailable.
