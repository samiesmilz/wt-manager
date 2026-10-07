<div align="center">

# wt-manager

**Too many worktrees. Too much disk. One clear next step.**

A native macOS menu-bar companion for developers working across Git branches, projects, and coding agents.

[Install](#install) · [How it works](#your-first-five-minutes) · [Safety](#cleanup-with-a-review-first) · [CLI](#the-same-tool-in-your-terminal)

![wt-manager overview with example projects](docs/images/overview.png)

</div>

A Git worktree is another checkout of a repository, with its own files and branch. It makes parallel work easy. It also makes it easy to forget a finished branch, leave a dependency folder behind, or lose track of work that exists only on your laptop.

wt-manager answers three questions:

- **What needs me?** See active work, review requests, failing checks, forgotten branches, and finished checkouts.
- **Where did my space go?** Measure checkout sizes, find rebuildable output, and watch disk usage change between full scans.
- **What can I safely clean?** Review the exact paths first. Keep work at risk in place. Preserve protected files before removing eligible worktrees.

No hosted account. No subscription. A Python standard-library engine, a native SwiftUI app, and a pixel companion that lives in your menu bar.

## Install

### Download the app — Apple Silicon

1. Download `wt-manager-macos-arm64.zip` from the [latest release](https://github.com/samiesmilz/wt-manager/releases/latest).
2. Unzip it and move **wt-manager.app** into **Applications**.
3. Open the app. Choose the folders containing your repositories.

You need **macOS 13 or later**, **Git**, and **Python 3.9 or later**. The app looks for Python in the standard Apple and Homebrew locations. It does not bundle a Python runtime. GitHub pull-request enrichment is optional and requires the [GitHub CLI](https://cli.github.com/) signed into accounts that can read your repositories.

This initial release is **ad-hoc signed, not Apple notarized**. macOS may ask you to approve opening it in System Settings → Privacy & Security. If you prefer building the code yourself, use the source installation below. Intel Macs can build from source; the downloadable binary is for Apple Silicon.

The downloaded app starts when you open it. To launch it at login, add it in System Settings → General → Login Items. Source installation can configure this for you.

### Build from source

Install Xcode Command Line Tools (or Xcode with a Swift 5.9+ toolchain), Git, and Python 3.9+. Then:

```sh
git clone https://github.com/samiesmilz/wt-manager.git
cd wt-manager
make install
```

This builds the app, installs it into `/Applications`, links the CLI at `~/.local/bin/wt-manager`, and registers a login item. Add `~/.local/bin` to your shell's `PATH` if it is not already there.

To install without launching at login:

```sh
LOGIN=0 make install
```

The app and CLI share the engine inside the installed bundle, so they use the same safety rules.

## Your first five minutes

1. **Choose watched folders.** Select a parent such as `~/dev`. wt-manager searches up to three directory levels deep for repositories.
2. **Read Overview.** Get the next useful action, project summaries, and work that exists only on this machine.
3. **Open Disk.** See space per repository, rebuildable output, and the latest measured growth. The first full scan can take a few minutes; counts appear first and disk measurement runs behind them.
4. **Review cleanup.** Read the exact paths and preservation details. Nothing is deleted during the preview.
5. **Confirm deliberately.** Only confirmed completions earn reclaimed-space credit. Results remain available after the modal closes.

The sidebar separates **Needs you**, **Forgotten**, **In flight**, **With others**, **Finished**, and **Main checkouts**. Filter by repository or branch, expand a checkout for details, or hand work off to Terminal, Finder, or its pull request.

“Finished” describes branch history. It does not automatically mean “safe to delete.” A checkout with local changes or another known blocker explains why removal is unavailable. Unchecked checkouts offer inspection first.

## Cleanup with a review first

wt-manager has two different actions:

| Action | What changes | What stays |
|---|---|---|
| **Clean build output** | Recognized rebuildable folders such as dependency/build output | The checkout, environment files, keys, and unrecognized files |
| **Remove eligible worktrees** | Finished, eligible extra checkouts via `git worktree remove` | Work at risk; verified copies of protected local files |

Removal checks local changes, unpushed work, base resolution, locks, submodules, and unknown-file size. Primary/base checkouts are kept. Protected ignored files, such as environment files, are copied to `~/.local/share/wt-manager/kept/` and verified byte for byte before removal. Recognized output containing protected descendants preserves those descendants without archiving the whole build folder. Truly unclassified data over the backup limit (100 MB) blocks removal.

The preview and confirmation are bound to the same reviewed set. If that set changes, the operation asks for another review. Execution can still refuse if permissions, files, or Git state change. Partial results list only confirmed completions and show what failed.

**Deletion is consequential.** Preserved local files are not a full checkout backup. Read the preview and keep your own backups. Rebuildable output must be installed or built again.

## Make space. Get a little celebration.

![Local reclaim badges and measured disk growth](docs/images/rewards.png)

Your **Space** card tracks local progress:

- Estimated reclaimed space and confirmed cleanup count.
- Badges at **1, 5, 25, 100, and 500 GiB**, from **Space Scout** to **Space Legend**.
- Watched-checkout size, rebuildable space, and change since the previous full measurement.
- A compact history line for the last 48 full scans.

A successful cleanup in the app triggers a short burst of pixel sparks. Partial successes earn credit for confirmed reclaimed space but keep warning feedback prominent. Failed operations and previews earn nothing. There are no streak penalties or leaderboards. Badge credit is recorded for cleanups performed through the native app; CLI changes appear in subsequent disk measurements.

Measurements and rewards stay on your Mac. Changing watched folders resets the comparison baseline so a different scope does not appear as disk growth. Figures are estimates from the engine, not a filesystem quota or a promise of exact free-space changes. Sparse files, shared objects, and rebuilds can affect actual disk use.

Turn effects off in **Appearance → Cleanup celebrations**. macOS **Reduce Motion** disables the particle burst and mascot motion; readable completion feedback stays.

## Meet the pixel crew

![Original pixel mascots at header and menu-bar sizes](docs/images/mascots.png)

| Companion | Personality |
|---|---|
| **Wity** | The original cat, with a plume and status collar |
| **Nipper** | A crab with snapping claws and tiny legs |
| **Byte** | An original dark robot face with a visor, signal lights, and a small smile |
| **Cooper** | A rooster with a red comb, golden beak, and a proud head bob |
| **Pip** | A bright rabbit with long ears and little paws |

Pick a character and coat in **Appearance**. You can also use your own picture, reduced to the same pixel grid and stored locally.

**Tap the large mascot for its menu: change coat, check for updates, or quit.** The menu-bar mascot also offers Open window, Refresh, Watched folders, updates, and Quit. Quit is unavailable while a destructive operation is running. Closing the window leaves the menu-bar companion running; quitting stops the app until you open it again or the next configured login launch.

## Updates

The app checks this repository's latest stable GitHub release at launch and then no more than once a day after a successful check. A new version appears in a dismissible banner with a link to the release and installation instructions. You can always check manually from either mascot menu or Appearance.

Updates are **announced, not silently installed**. To update a downloaded app, quit wt-manager and replace it with the new download. For a source install, update your checkout and run `make install` again. Settings and local reward history survive replacement.

Turn automatic checks off in **Appearance → Check updates automatically**. Checks contact GitHub's public release API without an authentication token or repository data. GitHub receives ordinary network metadata such as your IP address and the installed app version. Offline or failed checks are shown honestly when requested manually; they do not erase a previously discovered update.

## The same tool in your terminal

For a source installation, the CLI is linked automatically. For a downloaded app, optionally link its embedded engine:

```sh
mkdir -p "$HOME/.local/bin"
ln -sf /Applications/wt-manager.app/Contents/Resources/engine/wtmanager.py "$HOME/.local/bin/wt-manager"
```

Add `~/.local/bin` to your `PATH`, then:

```sh
wt-manager                    # work across watched repositories
wt-manager --all              # include finished and primary checkouts
wt-manager --here              # just the current repository
wt-manager size                # measure checkout and rebuildable sizes
wt-manager doctor              # explain base resolution and forge access
wt-manager --json              # machine-readable inventory
wt-manager clean               # preview rebuildable-output cleanup
wt-manager reap                # preview eligible worktree removal
```

Explicitly act on a checkout after reviewing it:

```sh
wt-manager clean --path /path/to/worktree --yes
wt-manager reap --path /path/to/worktree --yes
```

For scripts, bind confirmation to the preview hash with `--json` and `--plan HASH`. Read `wt-manager --help`, `wt-manager clean --help`, and `wt-manager reap --help` for the complete options, including advanced overrides. The app uses the conservative defaults.

Configure folders and bases:

```sh
wt-manager config --init
wt-manager config --roots ~/dev --roots ~/projects
wt-manager config --clear-cache
```

## What is read, stored, and sent

- **Git repositories:** local refs, status, worktree metadata, and directory sizes. wt-manager never performs `git fetch` or changes a branch's history.
- **GitHub PRs:** optional queries through `gh`. Multiple signed-in accounts are tried per repository without changing your active CLI account. Without `gh`, local Git inventory still works.
- **Update checks:** the public release endpoint for this project. No scanned paths, branch names, disk measurements, reward data, or PR data are included in update requests.
- **Local settings:** watched folders/base pins under `~/.config/wt-manager/`; caches under `~/.cache/wt-manager/`; preserved files under `~/.local/share/wt-manager/kept/`; native appearance, rewards, and measurements in app preferences. Custom images live in Application Support.

Counts refresh about every five minutes, disk measurements about hourly. Opening the window catches up on stale counts. Cached sizes can lag changes outside the app; Refresh requests a full measurement. Duplicate/shared repository content means summed checkout estimates are not an exact measure of unique physical bytes.

## Shortcuts and lifecycle

| Shortcut | Action |
|---|---|
| `⌘R` | Refresh and measure disk |
| `⌘F` | Find a checkout |
| `⌘,` | Watched folders |
| `⌘1`–`⌘9` | Navigate sections |

From a source checkout:

```sh
make stop         # stop until explicitly started or the next login
make start        # launch again
make login-off    # disable launch at login
make login-on     # enable launch at login
make uninstall    # remove app, CLI link, and login item
```

Uninstall intentionally leaves settings, caches, reward history, and preserved files. Backups are yours to retain or remove. `wt-manager config --clear-cache` only clears the engine's caches.

## Development

```sh
python3 -m unittest -q test_wtmanager
swift test --package-path app
make bundle
make snapshots
```

The native render harness covers light/dark appearance, normal/minimum window sizes, setup, every section, safety/refusal states, progress, success, and partial failures. Documentation screenshots use fictional projects. Accessibility support includes named controls, keyboard shortcuts, persistent text results, and Reduce Motion; a complete VoiceOver certification has not been performed.

See [CONTRIBUTING](CONTRIBUTING.md) for development and [RELEASING](RELEASING.md) for publishing a release. Report reproducible bugs through [Issues](https://github.com/samiesmilz/wt-manager/issues). When reporting cleanup problems, redact private paths and file contents.

## License

[MIT](LICENSE). Built by [Samuel Abinsinguza](https://github.com/samiesmilz).
