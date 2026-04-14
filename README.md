# AzureGallery

**A local-first iOS photo gallery with Azure Blob Storage backup.**

Your photos live on your phone. You browse them on your phone. Nothing changes about how you use your camera roll. In the background, AzureGallery quietly uploads every photo and video to your personal Azure Blob Storage account. If you lose your phone, buy a new one, or accidentally delete something — your entire library is sitting in Azure, ready to restore.

No servers to maintain. No subscriptions to a photo service. No third party ever touches your photos. Just your iPhone and your Azure account.

---

## The Problem

You take photos. Thousands of them. They live on your phone, and maybe iCloud. But iCloud costs money monthly, Apple controls the infrastructure, and if you ever leave the ecosystem you're starting over. Google Photos compresses your images and mines them for data. Every cloud photo service is a subscription you're locked into.

What if you could back up your entire photo library to storage you own, at a fraction of the cost, with zero infrastructure to manage?

Azure Blob Storage Cold tier costs **$0.0036 per GB per month**. A 50 GB photo library costs **$0.18/month** to back up. That's $2.16/year. For comparison, iCloud 50 GB is $0.99/month ($11.88/year) and Google One 100 GB is $1.99/month ($23.88/year).

## How It Works

```
┌─────────────────────────────────────────────────────┐
│                      iPhone                          │
│                                                      │
│   Camera Roll / Photo Library                        │
│        │                                             │
│        ├──── Gallery UI reads locally (zero network) │
│        │     Grid → Full screen → Pinch zoom         │
│        │     Videos, Live Photos, screenshots         │
│        │                                             │
│        └──── Backup Engine detects new photos        │
│              Queues for upload                        │
│              Tracks state in local SQLite             │
│                    │                                  │
│                    ▼                                  │
│           URLSession Background Transfer              │
│           (iOS manages this outside your app —        │
│            survives app kill, phone restart,           │
│            network interruption. Resumes              │
│            automatically.)                            │
└────────────────────┬────────────────────────────────┘
                     │
                     │  HTTPS upload (ingress — free on Azure)
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│            Azure Blob Storage (Cold tier)             │
│                                                      │
│   Container: photos/                                 │
│   ├── originals/2024/01/a8f3...c2.HEIC              │
│   ├── originals/2024/01/b91d...f7.MOV               │
│   ├── originals/2025/03/cf22...a1.HEIC              │
│   └── metadata/manifest.json                         │
│                                                      │
│   Your data. Your account. Your encryption keys.     │
│   No one else has access.                            │
└─────────────────────────────────────────────────────┘
                     │
                     │  Download (only during restore — rare event)
                     │  Egress cost: ~$0.01/GB
                     ▼
┌─────────────────────────────────────────────────────┐
│            New / Restored iPhone                      │
│                                                      │
│   App lists Azure blobs → downloads originals →      │
│   saves to Photo Library → iOS regenerates           │
│   thumbnails, indexes faces, rebuilds albums         │
└─────────────────────────────────────────────────────┘
```

**During normal daily use, the app never downloads anything from Azure.** You browse your local photo library like you always do. Azure is invisible until you need it.

---

## Features

### Gallery

The gallery is not a custom photo viewer. It's a native SwiftUI interface built on top of Apple's `PHPhotoLibrary` — the same system that powers the built-in Photos app.

- **Grid view** — scrollable timeline of all photos and videos, grouped by date. Uses `LazyVGrid` for smooth scrolling through thousands of items.
- **Full-screen viewer** — tap any photo for full resolution. Pinch to zoom. Swipe to navigate. All loaded from local storage, instant.
- **Video playback** — native `AVPlayer` integration. Play videos inline or full-screen.
- **Live Photos** — long press to play the motion component.
- **Media filters** — toggle between all media, photos only, videos only, screenshots, selfies, panoramas.
- **Backup status overlay** — small indicator on each photo showing if it's backed up (checkmark), pending upload (cloud icon), or failed (warning).
- **No custom caching layer** — `PHImageManager` handles thumbnail generation, memory management, and disk caching. Apple already solved this problem.

### Backup Engine

The backup engine runs as a background service that detects new photos and uploads them to Azure without user intervention.

**Detection:**
- On app launch: scans photo library, compares against local SQLite database, queues anything new.
- While app is open: listens to `PHPhotoLibraryChangeObserver` for real-time notifications when user takes a photo, receives an AirDrop, saves from Messages, etc.
- Each asset is identified by `PHAsset.localIdentifier` — a stable, unique identifier that persists across app reinstalls on the same device.

**Upload:**
- Uses `URLSession` with a background configuration. This is critical — iOS manages these transfers in a system-level daemon, completely independent of your app's process lifecycle.
- Uploads continue when the app is suspended, terminated, or the phone is locked.
- If the network drops mid-upload, iOS retries automatically when connectivity returns.
- If the phone restarts, pending uploads resume.
- Uploads are queued — not all fired at once. Configurable concurrency (default: 3 simultaneous uploads).
- Each file is uploaded as a block blob with `accessTier` set to `Cold` at upload time.

**Tracking:**
- Local SQLite database tracks every asset: identifier, blob name, size, media type, creation date, upload status, timestamp.
- States: `pending` → `uploading` → `uploaded` or `failed` → `perm_failed` (after 3 retries).
- The database is the single source of truth for "what's been backed up." The app never lists Azure blobs during normal operation.

**Efficiency:**
- Only uploads new photos. Never re-uploads existing ones.
- Respects user preferences: wifi-only mode (default), or allow cellular.
- Battery-aware: iOS throttles background transfers when battery is low.
- No duplicate detection needed — `PHAsset.localIdentifier` is globally unique.

### Restore

Restore is an on-demand operation for recovering your photo library onto a new device, or after accidental deletion.

- **Scan Azure** — lists all blobs in your container. Shows total count, total size, and how many are already in your local library.
- **Selective restore** — restore everything, or filter by date range, media type, or specific folders.
- **Download + import** — downloads original files from Azure, saves them to the iOS Photo Library via `PHPhotoLibrary.performChanges`. iOS then generates thumbnails, indexes faces, and rebuilds smart albums automatically.
- **Progress tracking** — real-time progress bar with file count, data downloaded, current file, estimated time remaining.
- **Pause / Resume** — long restores (50+ GB) can be paused and resumed. Progress persists in SQLite.
- **Conflict handling** — if a photo already exists locally (same identifier), skip it. No duplicates.

### Settings

- **Azure configuration** — SAS token or connection string. Container name. Validated on save with a test API call.
- **Auto-backup** — master toggle. When off, no uploads happen. Useful when traveling on metered connections.
- **Network preference** — wifi-only (default) or wifi + cellular. Cellular uploads show a data usage warning.
- **Backup status** — dashboard showing: total photos in library, total backed up, pending, failed. Last successful backup timestamp. Storage used in Azure.
- **Cost estimate** — calculates monthly and yearly Azure cost based on your backed-up data size.
- **Notifications** — optional push notification when a backup session completes, or when failures occur.

---

## Technical Architecture

### Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| UI framework | SwiftUI | Native, declarative, modern. No cross-platform overhead. |
| Photo access | PhotoKit (`PHPhotoLibrary`, `PHImageManager`) | Apple's official API. Handles permissions, thumbnails, change observation, iCloud photo streaming. |
| Upload transport | `URLSession` background configuration | Only reliable way to upload in background on iOS. Survives app termination. iOS-managed retries. |
| Azure communication | Raw REST API with SAS token (or `AzureStorageBlob` Swift SDK) | REST API is simpler, no heavy SDK dependency. SAS token provides scoped, time-limited access. |
| Local database | GRDB.swift (SQLite wrapper) | Lightweight, type-safe, migration support. SwiftData is an alternative but less mature for this use case. |
| Minimum iOS | 17.0 | Required for modern SwiftUI features (`Observable`, `NavigationStack`, improved `PhotosPicker`). |

### Why URLSession Background Transfers

This is the single most important architectural decision. iOS is hostile to background work. Most approaches fail:

| Approach | Problem |
|----------|---------|
| `BGAppRefreshTask` | 30 seconds max. Not enough time to upload a single video. |
| `BGProcessingTask` | Only runs when plugged in + wifi + idle. Unreliable timing. |
| `beginBackgroundTask` | 30 seconds after app suspension. Race condition for large files. |
| Keeping app in foreground | Terrible UX. Users don't want to stare at an upload screen. |

`URLSession` with `.background` configuration is different from all of these. When you create a background upload task, iOS hands the transfer to a system daemon (`nsurlsessiond`). Your app can be killed entirely — the upload continues. The system daemon handles:

- Chunked transfer for large files
- Automatic retry on network failure
- Respecting Low Data Mode and Low Power Mode
- Resuming after device restart
- Calling your app's delegate when transfers complete (even relaunching your app if needed)

This is the same mechanism used by iCloud Photos, Google Photos, WhatsApp, and every other app that reliably uploads in the background on iOS.

**Limitation:** you must write the file to a temporary location on disk before creating the upload task. You can't stream from `PHImageManager` directly to URLSession. The flow is: export asset to temp file → create background upload task → iOS handles the rest → delete temp file on completion callback.

### Blob Naming and Organization

```
photos/
├── originals/
│   ├── 2024/
│   │   ├── 01/
│   │   │   ├── a8f3e2c1-4b7d-4f9a-b8c2-1d3e5f6a7b8c.HEIC    (4.2 MB)
│   │   │   ├── a8f3e2c1-4b7d-4f9a-b8c2-1d3e5f6a7b8c.MOV     (12.1 MB, live photo video)
│   │   │   ├── b91de4f7-2a3c-4e8f-9d1b-6c7a8e9f0d2b.HEIC    (3.8 MB)
│   │   │   └── ...
│   │   ├── 02/
│   │   └── ...
│   └── 2025/
│       └── ...
└── metadata/
    └── manifest.json
```

**Blob name**: derived from `PHAsset.localIdentifier` by replacing non-alphanumeric characters with hyphens. This is unique per device, stable across app reinstalls, and deterministic (same asset always maps to same blob name).

**Directory structure**: `originals/<year>/<month>/`. Photos organized by their creation date (from EXIF or file metadata). This makes the container browsable in Azure Storage Explorer — you can find photos by date without the app.

**Live Photos**: stored as two blobs — the HEIC image and the MOV video component — with the same base name but different extensions.

**Manifest**: `metadata/manifest.json` is a periodically-updated index mapping blob names back to human-readable metadata:

```json
{
  "version": 1,
  "updated": "2025-03-15T10:30:00Z",
  "assets": {
    "a8f3e2c1-4b7d-4f9a-b8c2-1d3e5f6a7b8c.HEIC": {
      "originalFilename": "IMG_4521.HEIC",
      "creationDate": "2024-01-15T14:23:45Z",
      "mediaType": "image",
      "pixelWidth": 4032,
      "pixelHeight": 3024,
      "fileSize": 4200000
    }
  }
}
```

This manifest serves two purposes:
1. **Restore to new device**: maps blob names back to original filenames and dates.
2. **Disaster recovery without the app**: if you ever need to recover photos without AzureGallery, the manifest tells you what each file is.

### Upload State Machine

```
    New photo detected (library scan or change observer)
                │
                ▼
          ┌──────────┐
          │  pending  │  Queued in SQLite, waiting for upload slot
          └────┬─────┘
               │  Upload slot available, export asset to temp file
               ▼
         ┌───────────┐
         │ uploading  │  URLSession background transfer active
         └──┬─────┬──┘
            │     │
     success│     │failure
            ▼     ▼
    ┌──────────┐ ┌────────┐
    │ uploaded  │ │ failed │  URLSession retries up to 3x automatically
    └──────────┘ └───┬────┘
                     │  All retries exhausted
                     ▼
              ┌─────────────┐
              │ perm_failed  │  Requires manual retry from Settings
              └─────────────┘
```

### SQLite Schema

```sql
CREATE TABLE backups (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    asset_id        TEXT UNIQUE NOT NULL,     -- PHAsset.localIdentifier
    blob_name       TEXT NOT NULL,            -- Azure blob path
    size            INTEGER,                  -- File size in bytes
    media_type      TEXT,                     -- image | video | live_photo
    creation_date   TEXT,                     -- Photo creation date (ISO 8601)
    status          TEXT DEFAULT 'pending',   -- pending | uploading | uploaded | failed | perm_failed
    retries         INTEGER DEFAULT 0,
    uploaded_at     TEXT,                     -- When upload completed
    error           TEXT,                     -- Last error message
    created_at      TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_backups_status ON backups(status);
CREATE INDEX idx_backups_asset ON backups(asset_id);
```

---

## Azure Cost Breakdown

### Storage (Cold Tier)

| Library size | Monthly cost | Yearly cost |
|-------------|-------------|------------|
| 10 GB (2,500 photos) | $0.036 | $0.43 |
| 50 GB (12,500 photos) | $0.18 | $2.16 |
| 100 GB (25,000 photos) | $0.36 | $4.32 |
| 500 GB (with videos) | $1.80 | $21.60 |

### Operations

| Operation | Cost | When it happens |
|-----------|------|----------------|
| Upload (write) | $0.10 per 10,000 operations | Every photo backed up |
| List blobs | $0.05 per 10,000 operations | Only during restore scan |
| Download (egress) | $0.01 per GB (first 100 GB) | Only during restore |

### Real-world example

A typical user with 15,000 photos (60 GB), adding 200 photos/month:

- **Storage**: $0.22/month
- **Monthly uploads** (200 write ops): $0.002
- **Total**: **~$0.22/month** ($2.64/year)

Compare:
- iCloud 200 GB: $2.99/month ($35.88/year)
- Google One 100 GB: $1.99/month ($23.88/year)

**AzureGallery is 10-15x cheaper** and you own the storage.

---

## Security

### Authentication

Two approaches, from simple to robust:

**Option 1: SAS Token (recommended for personal use)**
- Generate a Shared Access Signature in Azure Portal
- Scope: single container, read + write + list permissions (no delete for safety)
- Expiry: set to 1-2 years, renew in-app
- Stored in iOS Keychain (encrypted at rest, protected by device passcode/biometrics)
- No server needed, no token refresh flow

**Option 2: Azure AD with MSAL (recommended for multi-user / enterprise)**
- User authenticates via Microsoft identity platform
- App receives OAuth tokens, auto-refreshes
- More complex but eliminates manual token management
- Supports conditional access, MFA, revocation

### Data Protection

- **In transit**: all Azure communication over HTTPS (TLS 1.2+)
- **At rest**: Azure Storage uses 256-bit AES encryption by default (Microsoft-managed keys). Optionally configure customer-managed keys via Azure Key Vault.
- **On device**: SQLite database stored in app's sandboxed container. Protected by iOS Data Protection (encrypted when device is locked).
- **No telemetry**: the app collects nothing. No analytics SDKs, no crash reporting services, no network calls except to your Azure account.

---

## Project Structure

```
AzureGallery/
├── AzureGalleryApp.swift                # App entry point, URLSession delegate setup
│
├── Models/
│   ├── BackupRecord.swift               # SQLite model for backup tracking
│   ├── AzureConfig.swift                # Connection settings model
│   └── BackupStats.swift                # Computed stats (counts, sizes, progress)
│
├── Services/
│   ├── PhotoLibraryService.swift        # PHPhotoLibrary wrapper
│   │                                      - Request permissions
│   │                                      - Fetch assets (with filters, sorting)
│   │                                      - Observe changes (PHPhotoLibraryChangeObserver)
│   │                                      - Export assets to temp files for upload
│   │
│   ├── BackupEngine.swift               # Core backup orchestration
│   │                                      - Scan library, diff against DB
│   │                                      - Queue pending uploads
│   │                                      - Manage upload concurrency
│   │                                      - Handle URLSession callbacks
│   │                                      - Update manifest.json periodically
│   │
│   ├── AzureBlobService.swift           # Azure Blob Storage client
│   │                                      - Upload blob (PUT with SAS)
│   │                                      - Download blob (GET with SAS)
│   │                                      - List blobs (GET with prefix)
│   │                                      - Check blob exists (HEAD)
│   │                                      - Set access tier
│   │
│   ├── RestoreService.swift             # Restore orchestration
│   │                                      - Scan Azure for all blobs
│   │                                      - Diff against local library
│   │                                      - Download missing files
│   │                                      - Import to Photo Library
│   │                                      - Progress tracking
│   │
│   └── DatabaseService.swift            # SQLite via GRDB
│                                          - Migrations
│                                          - CRUD for backup records
│                                          - Stats queries
│                                          - Bulk operations
│
├── Views/
│   ├── Gallery/
│   │   ├── GalleryView.swift            # Main photo grid (LazyVGrid + PHFetchResult)
│   │   ├── PhotoDetailView.swift        # Full-screen image viewer (pinch, swipe)
│   │   ├── VideoPlayerView.swift        # Video playback with AVPlayer
│   │   └── BackupBadge.swift            # Small overlay showing backup status per photo
│   │
│   ├── Backup/
│   │   ├── BackupStatusView.swift       # Dashboard: backed up / pending / failed counts
│   │   ├── BackupProgressView.swift     # Active upload progress
│   │   └── FailedUploadsView.swift      # List of failed uploads with retry buttons
│   │
│   ├── Restore/
│   │   ├── RestoreView.swift            # Restore landing page
│   │   ├── RestoreScanView.swift        # Azure scan results
│   │   └── RestoreProgressView.swift    # Download progress
│   │
│   └── Settings/
│       ├── SettingsView.swift           # Main settings screen
│       ├── AzureSetupView.swift         # SAS token input, connection test
│       ├── NetworkPrefsView.swift       # Wifi-only toggle, cellular warning
│       └── CostEstimateView.swift       # Monthly/yearly cost calculator
│
└── Utilities/
    ├── BlobNaming.swift                 # PHAsset.localIdentifier → blob path
    ├── FileExporter.swift               # Export PHAsset → temp file on disk
    ├── ManifestManager.swift            # Build + upload manifest.json
    └── KeychainHelper.swift             # Secure storage for SAS token
```

---

## Edge Cases and Considerations

### iCloud Photo Library
If the user has iCloud Photo Library enabled, some photos may be stored as low-resolution placeholders on device with full resolution in iCloud. When exporting for upload:
- Request the full-resolution version via `PHImageManager` with `.current` delivery mode
- If the original is in iCloud, iOS will download it first (this is transparent to our code but may take time)
- Handle the case where iCloud download fails (network issue) — mark as `failed`, retry later

### Live Photos
A Live Photo is two files: a HEIC image and a short MOV video. Both must be uploaded and both must be restored together. The blob naming convention uses the same base identifier with different extensions. The manifest tracks them as a single logical asset with `mediaType: "live_photo"`.

### Large Videos
4K 60fps videos can be several GB. `URLSession` background transfers handle large files well, but:
- Export to temp file takes time and disk space. Check available disk before exporting.
- If temp disk space is low, skip large videos and prioritize photos.
- Set a configurable max file size for auto-backup (e.g., skip files over 2 GB unless on wifi + charging).

### Photo Deletion
If the user deletes a photo from their library after it's been backed up:
- The backup in Azure remains (this is the point — it's a backup).
- The local SQLite record remains with `status: 'uploaded'`.
- On restore, the photo will reappear.
- Optional future feature: a "sync deletions" toggle that removes Azure blobs when local photos are deleted.

### Multiple Devices
`PHAsset.localIdentifier` is unique per device. The same photo on two iPhones has different identifiers. To handle this:
- Each device gets its own prefix in Azure: `originals/<device-id>/2024/01/...`
- Or: use a content hash (SHA-256 of first 1 MB) for deduplication across devices
- V1 can be single-device. Multi-device dedup is a V2 feature.

### App Store Review
Apple requires a clear privacy policy and purpose string for photo library access. The app must:
- Include `NSPhotoLibraryUsageDescription` in Info.plist with clear explanation
- Request permission at runtime with a clear UI explaining why
- Never access photos without explicit user consent
- Not upload photos before the user configures Azure and enables backup

---

## Comparison with Existing Solutions

| Feature | AzureGallery | iCloud Photos | Google Photos | Immich + AzureSync |
|---------|-------------|---------------|---------------|-------------------|
| Monthly cost (50 GB) | $0.18 | $0.99 | $1.99 | Electricity + $0.18 |
| Infrastructure | None | Apple manages | Google manages | Home server |
| Data ownership | You own it | Apple's cloud | Google's cloud | You own it |
| Privacy | No third party | Apple has access | Google has access | Fully private |
| Gallery quality | Native iOS | Native iOS | Good | Web-based |
| Background upload | Yes (URLSession) | Yes | Yes | N/A (server-side) |
| Offline gallery | Full (local-first) | Partial (placeholders) | Partial (cached) | Full (local) |
| Search/faces/AI | iOS built-in | Yes | Yes (best) | Yes (ML) |
| Multi-platform | iOS only | Apple only | All platforms | All platforms |
| Setup complexity | Moderate (Azure) | None | None | High (Docker) |

---

## Development Roadmap

### V1 — Core (MVP) -- DONE
- [x] Photo library permissions + grid gallery
- [x] Full-screen photo viewer with zoom
- [x] Azure Shared Key configuration + connection test
- [x] Scan library → detect new photos → queue uploads
- [x] URLSession background uploads to Azure Cold tier
- [x] SQLite tracking (pending/uploading/uploaded/failed)
- [x] Backup status dashboard (counts, last upload time)
- [x] Basic restore (scan Azure → download all → save to library)
- [x] Settings: wifi-only toggle, auto-backup toggle
- [x] Light/dark mode support

### V2 — Polish -- DONE
- [x] Backup status cloud badge on each photo in grid
- [x] Video playback with AVPlayer (inline + full-screen)
- [x] Selective restore by month with thumbnail previews (Azure Range GET)
- [x] Cost estimate calculator with per-tier Azure pricing
- [x] Storage usage dashboard (blob count + total size from Azure API)
- [x] Failed uploads list with manual retry
- [x] Manifest.json generation + upload
- [x] Push notifications (batch complete, app icon badge count)
- [x] In-app diagnostic logs with 24-hour expiry, share button, shake-to-share
- [x] Active uploads view with per-file progress bars, thumbnails, real filenames
- [x] Pause/resume backup
- [x] Configurable concurrent uploads (1–20, default 10)
- [x] Charge-only upload mode

### V3 — Advanced -- DONE
- [x] Multi-device support (device-prefixed blob paths via stable DeviceIdentifier)
- [x] SHA-256 content-hash deduplication (streaming 1MB chunks, cross-device)
- [x] Conflict resolution (HEAD check before upload — skip if blob exists)
- [x] Widget-ready backup status card (BackupWidgetData Codable for future WidgetKit)
- [x] 3-screen onboarding flow (Welcome → Photo Access → Azure Setup)
- [x] Background App Refresh (BGTaskScheduler, 15-min interval)
- [x] iCloud download progress indicator (cyan bar + percentage)
- [x] Bandwidth stats (bytes uploaded today/this month)
- [x] Storage tier picker (Hot/Cool/Cold/Archive, default Cold)
- [x] Multi-cloud support: Azure + Amazon S3 + Google Cloud Storage
- [x] Multi-provider mirroring (upload to all enabled providers)
- [x] ML-powered search via NLEmbedding (semantic query expansion)
- [x] Vision metadata search (scene labels, OCR text, face count, animals)
- [x] Tab bar upload progress indicator (circular Core Graphics)
- [x] Album-based backup selection (back up specific albums only)

### V4 — Future
- [ ] **Security**: App lock (Face ID / passcode gate on launch)
- [ ] **Security**: Client-side encryption (AES-256-GCM before upload, user passphrase-derived key)
- [ ] **Security**: Secure wipe (delete local photos after confirmed upload, with undo window)
- [ ] **Reliability**: Exponential backoff retry (instead of flat 3 retries)
- [ ] **Reliability**: Post-upload integrity check (HEAD blob, compare Content-MD5 with local hash)
- [ ] **Search**: Full-text search on OCR results (currently stored but not indexed)
- [ ] **Search**: Date range filter in search view
- [ ] **Search**: Location-based search (GPS → reverse geocode → searchable place names)
- [ ] **Search**: Similar photo detection (VNFeaturePrint perceptual hash clustering)
- [ ] **Sync**: Full device restore (bulk download all blobs back to device)
- [ ] **Sync**: Selective sync (keep only thumbnails locally, full-res in cloud, download on demand)
- [ ] **Sync**: Manifest sync (upload manifest periodically so other devices can discover backups)
- [ ] **Sync**: Sync deletions (optional: remove cloud blob when local photo is deleted)
- [ ] **UX**: Photo editing (crop/rotate/filters before or after backup)
- [ ] **UX**: Shared albums (generate SAS URL / presigned URL with expiry for sharing)
- [ ] **UX**: Favorites sync (star locally → tag blob metadata in cloud)
- [ ] **UX**: WidgetKit home screen widget (backup progress, last backup time)
- [ ] **UX**: Siri Shortcuts ("Back up my photos" voice command)
- [ ] **UX**: iPad support with multi-column gallery
- [ ] **UX**: watchOS complication showing backup status
- [ ] **Cost**: Auto-cleanup old blobs (configurable retention policy)
- [ ] **Cost**: Compression before upload (HEIC quality slider, video transcoding to H.265)
- [ ] **Cost**: Large file handling (skip files over configurable size unless on wifi + charging)
- [ ] **Platform**: Backblaze B2 provider (S3-compatible API, even cheaper storage)
- [ ] **Platform**: MinIO / self-hosted S3 provider
- [ ] **Platform**: WebDAV provider (Nextcloud, Synology NAS)
- [ ] **Platform**: SFTP provider (any Linux server)
- [ ] **Platform**: Android version (Kotlin, same cloud backends)
