# Mascot design rules

Characters express personality; the framed badge communicates engine status.
Changing a character or coat must not change the strength or meaning of that signal.

- Use the same nine-pixel badge, borders and mood glyphs for every character, including custom pictures. Take the live tint and mood from the engine.
- Keep all eight moods distinguishable without colour. Two contrasting borders isolate the badge from coats and light/dark backgrounds.
- Use the shared 22×23 source grid and bottom baseline. Resting figures occupy at least 16 rows; intentional pecks may compress during motion.
- Give each character its own gesture: scanning lights, double peck, folding ears, hat-tip/wave and bending fronds. Avoid applying one whole-sprite bob to the cast.
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
```

Inspect light and dark images at their real size. Raster tests cover badge consistency across every character, mood and coat; other tests check glyph uniqueness, contrast, baselines and distinct alarm expressions. These checks establish consistency, not artistic quality or complete accessibility coverage. Live desktop movement and assistive-technology behaviour still need device testing.
