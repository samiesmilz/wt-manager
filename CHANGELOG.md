# Changelog

## 0.6.0

- Draw separate 32×32 pixel companions for Byte, Cooper, Pip, Flurry and Coco, with shading and recognizable character details.
- Render floating characters at 64×64pt inside the existing movable window; preserve simplified menu-bar artwork and status badges.
- Animate individual lights, ears, wing/peck, twig/scarf and fronds while keeping the feet grounded.
- Add a warm chestnut coat for Pip, retaining saved coat preferences.
- Keep older mascot data and the original characters usable through fallback rendering.

## 0.5.0

- Block cleanup/removal when Git reports an incomplete inventory, even with a successful exit code.
- Report skipped checkouts and preserve incomplete-scan warnings.
- Give every mascot the same framed status badge with eight distinct mood glyphs and tested contrast.
- Align character baselines, enlarge/lighten Byte, adjust Cooper and Coco coats, and restore Coco alarm eyes.
- Fix dark appearance in cast/motion snapshot modes.
- Make automatic update checks opt-in for new installations.

- A folder that cannot be read during the secret check — one a running build deletes mid-scan, say — no longer ends the whole scan with "scan refused". That worktree alone is marked unverified and refuses removal until a later scan reads it; everything else still refreshes.
- Installed-package folders (`node_modules`, `.pnpm`, `vendor`, `Pods`, `Carthage`, `site-packages`, `bower_components`) are checked for secrets at their top level only. A package's own `credentials.js` is no longer mistaken for yours, which had turned every `node_modules` into "unknown" and kept `clean` from removing it.

## 0.4.1

- Give Byte scanning signal lights, Cooper a double peck, Pip folding ears, Flurry a hat-tip and twig wave, and Coco independently reshaped fronds.
- Keep the new figures planted instead of sharing a generic bob/sideways shift.
- Reduce the floating companion from an 88×92pt drawing to 66×69pt.

## 0.4.0

- Add Flurry the snowman and Coco the palm tree, with animated pixel silhouettes and matching coats.
- Restore the movable desktop mascot, shown by default, with click/right-click menu access.
- Remember its position across launches; recover it after display changes.
- Add Show floating mascot and Reset mascot position controls.
- Keep the desktop, header, and menu-bar mascots on the same state and animation clock.

## 0.3.2

- Both background scans and previews use shared child-process shutdown tracking.
- Added regression coverage for termination and work queued after Quit.

## 0.3.1

- Quit now ends the app's read-only background engine scan instead of leaving it running.
- Normal app termination cannot interrupt a confirmed cleanup that is still applying changes.
- Zero reclaimed space is displayed explicitly as `0 B`.

## 0.3.0

First standalone public release: native worktree overview and disk measurement,
engine-backed cleanup previews and preservation, local growth history and reclaim
badges, pixel celebrations, stable-release notifications, mascot quit menus, and
original robot-face, rooster, and rabbit companions.
