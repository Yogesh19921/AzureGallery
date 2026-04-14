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
- `S3BlobService` — AWS Signature V4, virtual-hosted URLs
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
