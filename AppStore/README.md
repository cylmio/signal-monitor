# Mac App Store build

This directory defines the sandboxed Mac App Store variant of Signal Monitor.
It shares the UI and state model with the direct-download build, but reads Codex
data natively with SQLite after the user explicitly grants read-only access to
the hidden `~/.codex` folder.

The Store target does not install hooks, invoke Node.js or `sqlite3`, connect to
a private socket, or modify the selected Codex data folder.

## Generate and test

```sh
swift test
./scripts/generate_app_store_project.sh
xcodebuild \
  -project AppStore/Generated/SignalMonitorAppStore.xcodeproj \
  -scheme SignalMonitorAppStore \
  -configuration Debug \
  build
```

The generated Xcode project is intentionally ignored by Git. The checked-in
CMake definition is the source of truth. Release builds are universal binaries
for Apple Silicon and Intel Macs.

## Archive and export

```sh
xcodebuild \
  -project AppStore/Generated/SignalMonitorAppStore.xcodeproj \
  -scheme SignalMonitorAppStore \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath /private/tmp/SignalMonitorAppStore.xcarchive \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath /private/tmp/SignalMonitorAppStore.xcarchive \
  -exportPath /private/tmp/SignalMonitorAppStoreExport \
  -exportOptionsPlist AppStore/ExportOptions.plist \
  -allowProvisioningUpdates
```

To upload the archive without submitting it for review, replace
`AppStore/ExportOptions.plist` with `AppStore/UploadOptions.plist`. This requires
an existing App Store Connect app record for `com.caiyuli.signalmonitor`.

Before upload, increment `CFBundleVersion` in `Resources/AppStoreInfo.plist` and
verify the archive's sandbox entitlements and both `arm64` and `x86_64` slices.

## Reviewer path

On first launch, choose **Choose Codex Data Folder…** and select the hidden
`~/.codex` directory. **Use Demo Mode** provides four local example tasks for
reviewers who do not have Codex task data on their Mac.
