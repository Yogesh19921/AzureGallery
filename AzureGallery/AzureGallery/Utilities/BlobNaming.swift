import Foundation
import Photos

/// Generates deterministic Azure Blob Storage path names from PHAsset metadata.
///
/// Path format: `originals/<year>/<month>/<sanitized-localIdentifier>.<EXT>`
///
/// The path is derived entirely from the asset's creation date and local identifier,
/// so the same asset always maps to the same blob name. This makes deduplication
/// and re-upload detection cheap — just compare `blobName` against the DB record.
enum BlobNaming {

    /// Primary blob name for a photo or video asset.
    /// Example: `originals/2024/01/3E0A4F8B-9C2D-L0-001.HEIC`
    static func blobName(for asset: PHAsset) -> String {
        let date = asset.creationDate ?? Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = String(format: "%02d", calendar.component(.month, from: date))
        let sanitized = sanitize(asset.localIdentifier)
        let ext = fileExtension(for: asset)
        return "originals/\(year)/\(month)/\(sanitized).\(ext)"
    }

    /// Companion MOV blob name for the video component of a Live Photo.
    /// Both blobs (HEIC + MOV) share the same base path, differing only by extension.
    static func livePhotoBlobName(for asset: PHAsset) -> String {
        let date = asset.creationDate ?? Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = String(format: "%02d", calendar.component(.month, from: date))
        let sanitized = sanitize(asset.localIdentifier)
        return "originals/\(year)/\(month)/\(sanitized).MOV"
    }

    /// Strips characters not safe for blob path segments, replacing them with dashes.
    /// PHAsset localIdentifiers contain slashes (e.g. "UUID/L0/001") that would be
    /// misinterpreted as path separators if left unescaped.
    static func sanitize(_ identifier: String) -> String {
        identifier
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined(separator: "-")
    }

    private static func fileExtension(for asset: PHAsset) -> String {
        if asset.mediaType == .video { return "MOV" }
        // Default to HEIC; a future improvement could inspect the asset's UTType
        // for JPEG/PNG/GIF originals and preserve their native extension.
        return "HEIC"
    }
}
