# Publishing a release

1. Run the Python and Swift tests and inspect native snapshots.
2. Update `VERSION` in `wtmanager.py` and the development fallback in
   `UpdateChecker.currentVersion`. Installed builds read their bundle version.
3. Commit the reviewed source using your personal Git identity.
4. On an Apple Silicon Mac, run `make bundle`. Verify signing:

   ```sh
   codesign --verify --deep --strict app/wt-manager.app
   mkdir -p dist
   ditto -c -k --sequesterRsrc --keepParent app/wt-manager.app dist/wt-manager-macos-arm64.zip
   shasum -a 256 dist/wt-manager-macos-arm64.zip > dist/SHA256SUMS
   ```

5. Tag the reviewed commit (for example `v0.3.0`), push the source/tag, then
   publish a **stable GitHub release** with the zip and checksum file attached.
   Include installation/update instructions, supported architecture, known limits,
   and the fact that the initial binaries are ad-hoc signed and not notarized.

The updater reads `/repos/samiesmilz/wt-manager/releases/latest`; a tag alone is
not an update notification. Drafts and prereleases are excluded. Keep release
versions numeric `major.minor.patch`; compare `0.10.0` numerically, not as text.

Release assets contain only the app bundle, engine, and mascot data. Do not package
local preferences, caches, preserved files, real-repository snapshots, or the private
Toolshed repository/history. Apple notarization and an Intel/universal downloadable
build can be added once verified with the appropriate toolchain/signing identity.
