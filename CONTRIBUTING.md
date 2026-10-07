# Contributing

Build with macOS 13+, Swift 5.9+, Git, and Python 3.9+. GitHub CLI is optional.

The Python engine owns classification, cleanup eligibility, previews, and execution.
The SwiftUI app renders its results. Shared Swift models/renderers live in
`app/Sources/WTManagerKit`; original pixel art is defined in `mascot.py`.

Before changing removal or cleanup, add regression coverage with disposable Git
repositories. Never exercise destructive tests on your own working projects.
Run the Python and Swift suites listed in the README. Regenerate `mascot.json`
with `python3 mascot.py mascot.json` after art changes.

Use `make snapshots` to check both appearances and minimum widths. Use fictional
fixtures in public screenshots and bug reports; never publish private branch names,
file contents, tokens, or repository paths. Check partial failure and changed-plan
states as carefully as success. Keep progress and rewards tied to confirmed results.

Open an issue with the app version, macOS version, reproduction steps, expected
behavior, actual behavior, and redacted output/screenshots when useful.
