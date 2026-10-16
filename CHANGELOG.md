# Changelog

## 0.12.1

- Disk opens on what can be freed. Reclaim comes first, then By repo, and the Your space history last. Your space leaves Overview, so it appears once, beside the space it counts. It used to fill a narrow window's whole first screen with nothing to act on.
- Reclaim's headline names only the parts there are: "38GB of rebuildable output", plus the folders safe to delete when there are any. It read "— in 0 folders safe to delete". "Open Folders" is now a link.
- By repo:
  - The two numbers have column headings (REBUILDABLE, TOTAL).
  - Each bar is grey for what stays and green for what a build would put back, the same green that means "could free" everywhere else. It used to be one decorative hue per row.
  - The title reads "218GB across 33 repos", not "in worktrees".
  - The top eight show, with "Show N more".
  - Clicking a repo opens its folders, or Repos when it has none.
  - An unmeasured repo says "not measured" instead of a bare dash.
  - Two repos with the same name stay two rows.
- Folders says "No folders match" with a link to clear the filter when a search or project filter hides everything.
- "Reclaim build output from forgotten work" now reads "…from idle folders".

## 0.12.0

- **One page per job.** The sidebar is now Overview, Folders, Repos and Disk. Folders becomes the page for every worktree you made: it gains the list's search and project filter, and clicking a folder opens the same details the list showed (the commits that exist only here, base, ahead and behind, the pull request, with Reveal and Terminal). All worktrees, Needs you, In flight and With others are retired. **Repos** lists every checkout that is not a folder, including main checkouts with a feature branch out, so the two pages hold all of them, once.
- Fix: the arrow on a folder opened an empty page. The list filters a project by its `.git` path, and the arrow and the at-risk rows set its display name, so nothing matched. One `show` now lands on the worktree, opens it and scrolls it into view, on Folders or Repos.
- Overview:
  - The cards now run Do this next, At risk, Pull requests, By project, and Your space last.
  - The "N commits only on this machine" and "branches have gone quiet" items leave Do this next. The At Risk card lists the commits and opens each one.
  - A failing PR reads "A check is failing on …".
  - By project's FORGOT column is now SAFE, folders safe to delete.
- The character picker opens when you click your character, rather than filling the top of every page. "Next character" moves to the character's menu.
- A sidebar click or ⌘1–4 starts a page without old filters; a link from another page keeps the filter it set.

## 0.11.2

- After a delete, the page follows through: deleted folders fade out and the rest close up, a ticked folder that went is unticked, and the banner says "Deleted N folders", with **Show saved work** when edits, commits or set-aside files were kept. A partly failed delete now takes off the folders that did go at once, and re-measures only the ones that failed. Before, everything stayed on screen until a full measure minutes later.
- `--check-delete DIR PATH` runs the app's own delete on one real worktree, with no one at the window: preview, confirm, apply, refresh. It checks each step and draws the page before and after.
- Folders polish:
  - The sidebar counts every folder, as other entries do; it said "0" beside a page of 14.
  - When nothing is safe, a line says why.
  - Zero counts are hollow and unclickable, and all four pills always show.
  - Verdicts are a coloured dot and a quiet word, no longer twelve bold orange labels.
  - Card titles show the folder name in bold after a muted path, in the window's own type, so a narrow window cuts the path, not the name.
  - "Elsewhere" gets a plain folder icon.
  - A card with nothing safe says "Select in progress".
  - The subtitle fits on one line.
- Sizes move up a unit at a thousand of the smaller one: "1.0GB", not "1015MB" beside "2.8GB". The engine, the mascot and the app change together.

## 0.11.1

- The Forgotten and Finished sections are retired. Folders answers what both were for, what can go, for every worktree at once, and stale, merged and empty worktrees remain in All worktrees. The header's "N forgotten" and "N finished" tags become one "N safe to delete" tag that opens Folders.

## 0.11.0

- New **Folders** section: every worktree shown as a folder, grouped by where it lives on disk, with one verdict each: safe to delete, in progress, unsaved work, or kept. Folders that sit alone in their parent are gathered into one "Elsewhere" card. **Clear everything safe** and a per-folder clear do the start-of-sprint cleanup with a preview first. Each row has its own delete, or a link to what it holds.
- **Delete anyway**: a folder with unsaved work, or with unrecognised files too large to set aside, can be deleted when you are done with it. It still gets a copy first: edits are saved as a patch, commits stay on their branch, and commits on no branch are saved as a verified git bundle with the command to restore them. Only the oversized unrecognised files are deleted outright, and the preview lists them under their own heading. Locked worktrees and ones with submodules stay off-limits. CLI: `reap --folders --discard-work`.
- **Select several folders**: a checkbox on each row and "Select all" on each card. A bar shows how many are selected, their size and how many hold unsaved work, with one delete for the set. That button turns red when unsaved work is included.
- One number for what can be freed: the balloon, the Disk page and Overview's "Do this next" now count exactly the folders the Folders page calls safe. Before, the Disk page said 0 worktrees could be freed while Folders listed 12 safe ones.
- The count pills (safe, in progress, unsaved, kept) filter the page. Clicking anywhere on a row ticks it. "Select all" picks only folders that lose nothing; unsaved ones are ticked one at a time. Unsaved and kept rows have no lone delete button: tick them, or choose "Delete anyway…" from the row's menu. Rows also offer "Show in worktree list" and "Reveal in Finder", and every control has a VoiceOver label.
- A quick refresh no longer flips a folder of unrecognised files from "kept" to "safe": only a full measure looks at those files, so the last verdict that did is kept until the next one.
- Deleting a folder whose commits stay on its branch now leaves a RESTORE.txt naming the branch and the commits.
- `reap --folders` and `--discard-work` refuse to run without `--path`. Unscoped, `--discard-work` would have reached every worktree on the machine.
- "Safe" now means deleting the folder loses nothing, not that the work finished. A branch on GitHub, merged or not, survives its folder, because `git worktree remove` keeps the branch. Your own unpushed commits, uncommitted edits and detached commits still keep a folder. The engine computes the verdict with the same check `reap --folders` applies, so a folder called safe is one the button removes.

## 0.10.2

- New: **Save changes and remove** for a worktree whose pull request merged with every commit inside it, held back only by uncommitted edits. The edits are saved first as a binary patch, untracked files are copied and verified, and a RESTORE.txt says how to put them back; then the worktree is removed. It shows on the worktree's row and in "Do this next", and the preview lists every file it saves. The plan's hash names those files, so an edit made after the preview is refused rather than discarded unseen. Commits made after a merge are new work and stay protected. CLI: `reap --discard-changes`.
- Fix: a repo that moved to a new remote (here `github`) but kept an old, unfetched `origin` was measured against the frozen `origin/main`. Its merged worktrees read as 100-200 commits ahead, stale, and could not be removed. The base now comes from `origin` only while origin knows its default branch; otherwise from the remote that does. Cached rows are re-measured once (state version 7).
- Fix: a full measure could fail with "dictionary changed size during iteration" when two measuring threads loaded the size cache at once.

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
