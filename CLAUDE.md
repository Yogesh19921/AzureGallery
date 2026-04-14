# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development

```bash
# Build for simulator
xcodebuild build -scheme AzureGallery -destination 'platform=iOS Simulator,name=iPhone 16'

# Build for device
xcodebuild build -scheme AzureGallery -destination generic/platform=iOS

# Run tests
xcodebuild test -scheme AzureGallery -destination 'platform=iOS Simulator,name=iPhone 16'

# Run single test class
xcodebuild test -scheme AzureGallery -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AzureGalleryTests/BackupEngineTests

# Lint (SwiftLint)
swiftlint lint --strict
swiftlint autocorrect

# Resolve Swift packages
xcodebuild -resolvePackageDependencies
```

Open `AzureGallery.xcodeproj` in Xcode for development. Minimum deployment target: **iOS 17.0**.

## Architecture

Local-first iOS photo backup app. Gallery reads entirely from local PhotoKit — zero network during daily use. Azure is write-only during normal operation, read-only during restore.

### Layer Overview

| Layer | Files | Responsibility |
|---|---|---|
| App entry | `AzureGalleryApp.swift` | URLSession delegate wiring, app lifecycle |
| Views | `Views/` | SwiftUI, read from `@Observable` services |
| Services | `Services/` | All business logic, no UI imports |
| Models | `Models/` | Value types, GRDB record types |
| Utilities | `Utilities/` | Stateless helpers |

### Critical: URLSession Background Transfers

The single most important architectural decision. `BackupEngine.swift` creates `URLSession` with `.background` configuration — uploads run in `nsurlsessiond`, a system daemon independent of the app process. The app can be killed mid-upload and iOS continues uploading. Flow:

```
PHAsset → FileExporter (temp file on disk) → URLSession background task → nsurlsessiond uploads → delegate callback → delete temp file
```

**Never** stream directly from `PHImageManager` to `URLSession`. The temp-file intermediary is required.

### Backup State Machine

`pending` → `uploading` → `uploaded`  
`uploading` → `failed` (auto-retry ×3 by URLSession) → `perm_failed`

SQLite (`backups` table) is the single source of truth. The app never queries Azure blobs to determine backup state during normal operation.

### Key Service Interactions

- `BackupEngine` depends on `PhotoLibraryService`, `AzureBlobService`, `DatabaseService`
- `BackupEngine` registers as `URLSessionDelegate` — must be the same instance across app launches (background session identifier must be consistent)
- `PhotoLibraryService` implements `PHPhotoLibraryChangeObserver` → notifies `BackupEngine` of new assets in real time
- `AzureBlobService` uses raw REST + SAS token (no heavy Azure SDK); SAS token lives in Keychain via `KeychainHelper`

### Blob Naming

`originals/<year>/<month>/<PHAsset.localIdentifier sanitized>.EXT`  
Live Photos = 2 blobs: same base name, `.HEIC` + `.MOV`. `ManifestManager` tracks both under one logical asset.

### iCloud Photo Library Edge Case

Assets may exist as low-res placeholders locally. `FileExporter` must request `.current` delivery mode from `PHImageManager`, which triggers iCloud download transparently. Handle download failure → mark `failed`, retry later.

### Multi-Device (V2+)

`PHAsset.localIdentifier` is device-scoped. V1 is single-device. V2 uses `originals/<device-id>/...` prefix or SHA-256 content hash for deduplication.

## Dependencies

Managed via Swift Package Manager:

- **GRDB.swift** — SQLite wrapper (type-safe, migration support). Preferred over SwiftData for this use case.
- **AzureStorageBlob Swift SDK** — optional; raw REST API is the default for lower overhead.
