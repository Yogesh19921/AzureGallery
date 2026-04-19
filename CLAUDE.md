# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development

```bash
# Build for simulator
xcodebuild build -scheme AzureGallery -destination 'platform=iOS Simulator,name=iPhone 17'

# Build for device
xcodebuild build -scheme AzureGallery -destination generic/platform=iOS

# Run tests (261 tests)
xcodebuild test -scheme AzureGallery -destination 'platform=iOS Simulator,name=iPhone 17'

# Run single test class
xcodebuild test -scheme AzureGallery -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AzureGalleryTests/DatabaseServiceTests

# Resolve Swift packages
xcodebuild -resolvePackageDependencies
```

Open `AzureGallery.xcodeproj` in Xcode for development. Minimum deployment target: **iOS 17.0**.

## Architecture

Local-first iOS photo backup app with multi-cloud support. Gallery reads entirely from local PhotoKit — zero network during daily use. Cloud providers are write-only during normal operation, read-only during restore.

### Layer Overview

| Layer | Files | Responsibility |
|---|---|---|
| App entry | `AzureGalleryApp.swift` | URLSession delegate wiring, BGTask registration, onboarding |
| Views | `Views/` | SwiftUI, read from `@Observable` services |
| Services | `Services/` | All business logic, no UI imports |
| Models | `Models/` | Value types, GRDB record types, cloud configs |
| Utilities | `Utilities/` | Stateless helpers |

### Critical: URLSession Background Transfers

`BackupEngine.swift` creates `URLSession` with `.background` configuration — uploads run in `nsurlsessiond`. The app can be killed mid-upload and iOS continues. Flow:

```
PHAsset → FileExporter (temp file) → SHA-256 hash → dedup check → HEAD check → URLSession background task → delegate callback → mirror to secondary providers
```

**Never** stream directly from `PHImageManager` to `URLSession`. The temp-file intermediary is required.

### Multi-Cloud Provider Architecture

`CloudStorageProvider` protocol abstracts all cloud operations. Three implementations:
- `AzureBlobService` — Shared Key (HMAC-SHA256), REST API
- `S3BlobService` — AWS Signature V4. Serves **all S3-compatible providers** (AWS S3, Backblaze B2, Cloudflare R2, Wasabi, MinIO, etc.) via `S3Config.customEndpoint`. When `customEndpoint` is nil → virtual-hosted AWS URL; when set → path-style `https://endpoint/bucket`. Presets live in `S3Config` (`endpointTemplate` per preset).
- `GCPBlobService` — HMAC keys (S3-compatible signing), path-style URLs

`CloudStorageFactory.makeAllEnabled()` returns all configured+enabled providers. Primary provider uses background URLSession. After success, `mirrorToSecondaryProviders()` uploads to additional providers via foreground URLSession.

### Upload Path Optimization

Three-stage cost ladder before any network upload:
1. **Local hash dedup** (free) — SHA-256 of exported file, check DB for matching uploaded record
2. **Remote HEAD check** (1 round-trip) — does blob already exist? (handles reinstalls)
3. **PUT upload** — actual transfer via background URLSession

### Backup State Machine

`pending` → `uploading` → `uploaded`
`uploading` → `failed` (auto-retry ×3) → `perm_failed`

SQLite (`backups` table) is the single source of truth. DB migrations: v1 (core), v2 (vision metadata), v3 (content hash), v4 (bandwidth stats), v5 (search text + animal labels).

### Key Service Interactions

- `BackupEngine` depends on `CloudStorageProvider`, `PhotoLibraryService`, `DatabaseService`
- `NetworkMonitor` gates uploads (Wi-Fi only, charge only)
- `BackgroundTaskService` schedules BGAppRefreshTask every 15 min
- `NotificationService` fires local notifications + badge count
- `SemanticSearchService` expands search queries via `NLEmbedding`
- `VisionService` runs face detection, scene classification, OCR, animal detection

### Blob Naming

`originals/<device-id>/<year>/<month>/<PHAsset.localIdentifier sanitized>.EXT`

`DeviceIdentifier` generates a stable 8-char ID on first launch. Live Photos = 2 blobs: `.HEIC` + `.MOV`.

### Storage Tier Default

Default tier is **Cold** (Azure Cold / S3 GLACIER_IR / GCP COLDLINE). Configurable in Settings.

## Dependencies

- **GRDB.swift** — SQLite wrapper (type-safe, migration support)
- **CryptoKit** — HMAC-SHA256 signing for all three cloud providers, SHA-256 content hashing
- **NaturalLanguage** — NLEmbedding for semantic search query expansion
- **Vision** — Scene classification, face detection, OCR, animal recognition
- **BackgroundTasks** — BGAppRefreshTask scheduling
- **Network** — NWPathMonitor for connectivity state

## Test Suites (261 tests)

AppLoggerTests, AzureBlobServiceTests, AzureConfigTests, BackgroundTaskServiceTests, BackupEnginePauseTests, BackupRecordTests, BackupSelectionTests, BackupStatsTests, BackupWidgetDataTests, BlobNamingTests, DatabaseServiceTests, DeviceIdentifierTests, GCPBlobServiceTests, KeychainHelperTests, NetworkMonitorTests, NotificationServiceTests, OnboardingTests, S3BlobServiceTests, TabProgressTests

## Edge Cases

- **iCloud Photo Library**: Assets may be low-res placeholders. FileExporter requests `.current` delivery mode which triggers iCloud download transparently. Progress shown via cyan bar in Active Uploads.
- **Live Photos**: Two blobs (HEIC + MOV) with same base name. ManifestManager tracks both under one logical asset.
- **Large Videos**: 4K videos can be several GB. Background URLSession handles large files. Temp file disk space is the constraint.
- **Photo Deletion**: Backups in cloud remain after local deletion (that's the point). RestoreView shows cloud-only files for download.
- **Multi-Device**: `PHAsset.localIdentifier` is device-scoped. Device ID prefix in blob paths prevents collisions. SHA-256 content hash enables cross-device dedup.
- **App Reinstall**: `DeviceIdentifier` uses `identifierForVendor` which resets on reinstall. New uploads get a new device prefix. Old blobs still accessible via HEAD check (conflict resolution skips re-upload).

## Future Roadmap

### Security
- App lock (Face ID / passcode gate on launch)
- Client-side encryption (AES-256-GCM before upload, user passphrase-derived key)
- Secure wipe (delete local photos after confirmed upload, with undo window)

### Reliability
- Exponential backoff retry (instead of flat 3 retries)
- Post-upload integrity check (HEAD blob, compare Content-MD5 with local hash)

### Search
- Full-text search on OCR results (stored but not indexed yet)
- Date range filter in search view
- Location-based search (GPS → reverse geocode → searchable place names)
- Similar photo detection (VNFeaturePrint perceptual hash clustering)

### Sync
- Full device restore (bulk download all blobs back to device)
- Selective sync (thumbnails local, full-res in cloud, download on demand)
- Manifest sync (upload periodically so other devices discover backups)
- Sync deletions (optional: remove cloud blob when local photo deleted)

### UX
- Photo editing (crop/rotate/filters)
- Shared albums (SAS URL / presigned URL with expiry)
- Favorites sync (star locally → tag blob metadata)
- WidgetKit home screen widget
- Siri Shortcuts ("Back up my photos")
- iPad multi-column gallery
- watchOS complication

### Cost
- Auto-cleanup old blobs (configurable retention policy)
- Compression before upload (HEIC quality slider, video transcoding H.265)
- Large file handling (skip over configurable size unless wifi + charging)

### Platform
- WebDAV (Nextcloud, Synology NAS)
- SFTP (any Linux server)
- Android version (Kotlin, same cloud backends)

(Backblaze B2, Cloudflare R2, Wasabi, MinIO now supported via `S3BlobService` + `customEndpoint`.)
