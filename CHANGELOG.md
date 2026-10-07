# Changelog

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
