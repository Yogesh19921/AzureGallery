import Foundation
import Photos

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

    // Export a PHAsset to a temp file. Caller is responsible for deleting the file.
    static func export(asset: PHAsset) async throws -> URL {
        switch asset.mediaType {
        case .image:
            return try await exportImage(asset: asset)
        case .video:
            return try await exportVideo(asset: asset)
        default:
            throw ExportError.unsupportedMediaType
        }
    }

    private static func exportImage(asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true  // allow iCloud download
            options.isSynchronous = false

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

    private static func exportVideo(asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

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
