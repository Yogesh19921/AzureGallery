import Foundation
import Photos

enum BlobNaming {
    // originals/2024/01/<sanitized-asset-id>.HEIC
    static func blobName(for asset: PHAsset) -> String {
        let date = asset.creationDate ?? Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = String(format: "%02d", calendar.component(.month, from: date))
        let sanitized = sanitize(asset.localIdentifier)
        let ext = fileExtension(for: asset)
        return "originals/\(year)/\(month)/\(sanitized).\(ext)"
    }

    static func livePhotoBlobName(for asset: PHAsset) -> String {
        let date = asset.creationDate ?? Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = String(format: "%02d", calendar.component(.month, from: date))
        let sanitized = sanitize(asset.localIdentifier)
        return "originals/\(year)/\(month)/\(sanitized).MOV"
    }

    private static func sanitize(_ identifier: String) -> String {
        identifier
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined(separator: "-")
    }

    private static func fileExtension(for asset: PHAsset) -> String {
        if asset.mediaType == .video { return "MOV" }
        // Default to HEIC for images; could inspect UTType for more precision
        return "HEIC"
    }
}
