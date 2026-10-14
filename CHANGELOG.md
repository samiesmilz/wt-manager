# Changelog

## 0.10.1

- The pull-request card is redrawn: three equal Open/Merged/Closed tabs, one clickable row per PR with its state, number, repo and branch, and chips only for what asks something of you (checks failing, changes requested, draft, approved). PR numbers no longer show a thousands separator ("#2,242").
- One way to write a size everywhere, matching the engine: the window truncated 56.6 GB to "56GB" while the balloon rounded it to "57", so one measurement read as two. Sizes under a gigabyte now show in MB on the balloon too.
- Overview alignment pass: the At Risk figure now spans both lines of its caption instead of standing above the first; each "Do this next" colour bar runs the height of its text; the rewards progress bar is drawn in the card's green (the system bar came out grey) and the star lines up with the rank; the By project columns have room for their headings and one numeric style. "Review removal of 1 eligible worktrees" says "worktree".

## 0.10.0

- The floating character now holds a disk balloon showing how much wt-manager could free: finished worktrees that are free to go, plus rebuildable caches everywhere else. Green below 5 GB, yellow to 20 GB, orange above, one colour higher when the disk is over 90% full; it grows in three sizes and announces each half-gigabyte step.
- The balloon is held by each character's hand (or tied on), sways in a breeze from the side to almost overhead, trails and overshoots on strolls, tugs restlessly in orange, and floats away when there is nothing left to free. Reduce Motion holds it still.
- A new worktree is measured as soon as it appears (`agent --measure PATH`), so the balloon grows without waiting for the hourly measure.
- The floating window grows to 112×184pt for the balloon; only the character and balloon take clicks. The status badge leaves the floating character; the window and menu bar keep the mood.
- `--snapshot-balloon DIR` renders the floating view in each balloon state.
- The Disk badge and the Disk page now lead with the balloon's number, what you could free, split into finished worktrees and rebuildable output. One definition of a removable worktree serves the remove button and the balloon.
- Fix: removing worktrees subtracted their whole size from the rebuildable total, so 36 GB removed showed "32 GB" with 57 GB still there, and the engine carried the wrong figure until the hourly measure. Only their caches are subtracted now.
- The completion banner and rewards card say "freed" for this cleanup and "freed in all" for the running total, with the distance to the next rank, instead of two "reclaimed" figures side by side.

## 0.9.0

- Add Bork, a snow-white puppy with a red bandana, and Chomp, a tiny rex with arms that miss its mouth. Each has a front portrait, a menu-bar portrait and a walking profile.
- Bork trots on diagonal pairs with a wagging tail and a swinging ear; Chomp stomps on thick legs, its body dropping as each foot lands and its head a beat later. Both walk on the shared planted-foot gait, so neither skates.
- Keep Coco rooted in place: a gust sways its drawn fronds and trunk while the base and sand stay put. The old 76° topple rotated, shifted and shrank the whole tree to fit its window, so it looked like it was flying.
- Clicking or dragging the mascot now counts as a rest: it no longer walks off again a few seconds after you put it somewhere.
- Keep each character's drawn coat in one shared table instead of five copies.

- Expand walking to 16 poses with lifted recovery arcs and forward foot placement; align leg attachments so the recovering foot passes the planted foot.
- Match Wity and Nipper’s walking art to their original portrait grids and anchor all floating drawings to a shared foot baseline.
- Use smaller, more frequent advances at the same slow average pace, with hop-specific rabbit travel and snowman waddling.
- Blend walking/resting changes briefly; cancel that transition on interaction or Reduce Motion.
- Check planted-foot stability, airborne forward crossing, native 16-frame decoding, matching portrait dimensions, and character travel pace.

- Keep alternating steps steady without the extra hold; remove the long wandering subtext from Appearance.
- Allow mascot wandering with the main window open or closed; remove the close-window instruction.
- Advance the floating mascot and its walking pose together on each foot push; remove the independent window animation that made it slide.
- Hide the floating status arrow during walking and restore it at rest.
- Decode the companion's `walking_sprites` JSON field correctly; the native app was silently drawing idle frames during movement.
- Give all moving companions dedicated side profiles, mirrored for leftward travel; keep the front portraits for resting and Coco rooted.
- Slow the pace again to 12 points per second and choose short, mostly horizontal routes. Preserve that pace on long returns instead of accelerating to meet a time limit.
- Keep the walking feet clear of the status badge in either direction and redraw the pixel pose only when it changes.
- Check the actual main window rather than treating the menu-bar icon's window as an open app window; this restores wandering and floating merge messages.
- Unread merged-PR notices no longer stop mascot wandering indefinitely; speech banners stay still while the companion explores.
- Keep Coco rooted: the palm catches a gust, topples in place, and springs upright instead of walking around the screen.
- Slow strolls to a relaxed pace, advance the walking pose by distance travelled, and give the legged companions clear alternating planted and lifted steps.

## 0.8.0

- Add optional mascot strolls with character-specific pixel gaits, eased travel, natural pauses, turns and a return to the user's resting spot.
- Keep wandering off by default; pause it while wt-manager is open, when a merge message needs attention, and when macOS Reduce Motion is enabled.
- Let a click or drag interrupt a stroll immediately; never save random stops as the user's preferred position.
- Animate the walking pose only during movement and use native window easing between destinations.

## 0.7.3

- Draw dedicated 22px menu-bar icons with larger faces, clearer eyes and distinct silhouettes. Preserve Wity’s original drawing.
- Soften Pip’s face and muzzle; give Cooper a smaller head, slimmer neck, longer legs and alternating toe lifts.
- Keep menu-bar mascots clean by omitting the framed arrow/status badge, while preserving the attention count and status tooltip. Desktop and window badges remain.

## 0.7.2

- Make PR counters reveal their matching PR links; fetch titles and offer Open PR in merge messages and checkout details.

- Open the window immediately by clicking the desktop or menu-bar mascot; right-click retains maintenance actions.
- Select mascots with one click on always-visible portraits; the header mascot cycles characters.
- Preserve drag-to-move and make the accessibility press action open the window.

## 0.7.1

- Include the PR-engine changes in the tagged source release. The prebuilt 0.7.0 app already contained these changes; source builds now match the app.

## 0.7.0

- Add Mallow, a pearl orb, and Bop, a red antenna character, with different silhouettes and idle gestures.
- Keep Wity’s floating arrow badge small; use the same nine-point status badge across companions.
- Count known linked PRs as Open, Merged or Closed-not-merged, once per PR.
- Verify closed PR linkage against the checkout head; surface incomplete provider history.
- Track observed PR merges locally and show dismissible speech messages beside the floating mascot or in the window.
- Separate merge activity from removal eligibility when a checkout has newer commits. Review always opens a fresh safety preview.

## 0.6.1

- Replace the cross-shaped attention badge with a simple right-pointing arrow.

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
