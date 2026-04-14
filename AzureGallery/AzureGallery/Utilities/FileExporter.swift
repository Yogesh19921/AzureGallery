import Foundation
import Photos

/// Exports a PHAsset to a temporary file on disk so it can be read by a URLSession background upload task.
///
/// **Why a temp file?** Background URLSession uploads must read from a file URL, not a stream.
/// PHImageManager delivers data in callbacks, so we write it to a temp path first.
/// The caller (``BackupEngine``) is responsible for deleting the file after the upload completes.
enum FileExporter {
    enum ExportError: LocalizedError {
        case requestFailed
        case iCloudDownloadRequired
        case unsupportedMediaType

        var errorDescription: String? {
            switch self {
            case .requestFailed: return "Failed to export asset to file"
            case .iCloudDownloadRequired: return "Asset not available locally; iCloud download required"
            case .unsupportedMediaType: return "Unsupported media type"
            }
        }
    }

    /// A closure called periodically while the asset is being downloaded from iCloud.
    /// The `Double` parameter ranges from 0.0 to 1.0.
    typealias ICloudProgressHandler = @Sendable (Double) -> Void

    /// Export `asset` to a temporary file and return the URL.
    /// Triggers an iCloud download if the asset is not locally available.
    /// The caller must delete the file when the upload finishes.
    static func export(asset: PHAsset, iCloudProgress: ICloudProgressHandler? = nil) async throws -> URL {
        switch asset.mediaType {
        case .image:
            return try await exportImage(asset: asset, iCloudProgress: iCloudProgress)
        case .video:
            return try await exportVideo(asset: asset, iCloudProgress: iCloudProgress)
        default:
            throw ExportError.unsupportedMediaType
        }
    }

    private static func exportImage(asset: PHAsset, iCloudProgress: ICloudProgressHandler?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true  // allow iCloud download
            options.isSynchronous = false

            if let iCloudProgress {
                options.progressHandler = { progress, _, _, _ in
                    iCloudProgress(progress)
                }
            }

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: ExportError.requestFailed)
                    return
                }

                let ext = uti.flatMap { Self.extensionFromUTI($0) } ?? "HEIC"
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                do {
                    try data.write(to: tmpURL)
                    continuation.resume(returning: tmpURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func exportVideo(asset: PHAsset, iCloudProgress: ICloudProgressHandler?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            if let iCloudProgress {
                options.progressHandler = { progress, _, _, _ in
                    iCloudProgress(progress)
                }
            }

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(throwing: ExportError.requestFailed)
                    return
                }
                // Copy to temp location so URLSession can read it
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("MOV")
                do {
                    try FileManager.default.copyItem(at: urlAsset.url, to: tmpURL)
                    continuation.resume(returning: tmpURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func extensionFromUTI(_ uti: String) -> String? {
        switch uti {
        case "public.heic", "public.heif": return "HEIC"
        case "public.jpeg": return "JPEG"
        case "public.png": return "PNG"
        case "com.compuserve.gif": return "GIF"
        case "public.tiff": return "TIFF"
        default: return nil
        }
    }
}
