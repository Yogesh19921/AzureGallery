import Foundation
import Vision
import Photos
import UIKit

/// Aggregated Vision analysis results for a single PHAsset.
struct VisionAnalysis: Sendable {
    let faceCount: Int
    /// Normalized bounding boxes (0–1) for detected faces.
    let faceRects: [CGRect]
    /// Landmark points (eyes, nose, mouth) for each detected face.
    let faceLandmarks: [VNFaceLandmarkRegion2D]
    /// Top-5 scene classifications with confidence > 0.3.
    let sceneLabels: [(label: String, confidence: Float)]
    /// Lines of recognized text (OCR); useful for flagging screenshots.
    let recognizedText: [String]
    let animalLabels: [String]
    /// True if at least one human body pose was detected.
    let hasPersonSegmentation: Bool

    static let empty = VisionAnalysis(
        faceCount: 0, faceRects: [], faceLandmarks: [],
        sceneLabels: [], recognizedText: [], animalLabels: [],
        hasPersonSegmentation: false
    )
}

/// Runs Vision framework requests (face detection, scene classification, OCR, animals)
/// on a 512×512 thumbnail of a PHAsset. Analysis runs on a background thread.
///
/// Results are stored in ``BackupRecord`` Vision metadata fields and also included
/// in the Azure manifest for external use.
final class VisionService {
    static let shared = VisionService()
    private init() {}

    /// Full analysis: faces, scenes, OCR, animals. Runs off the main thread.
    func analyze(asset: PHAsset) async -> VisionAnalysis {
        guard let cgImage = await loadCGImage(for: asset) else { return .empty }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runRequests(on: cgImage)
                continuation.resume(returning: result)
            }
        }
    }

    /// Lightweight face-only pass. Synchronous; call from a background thread.
    func detectFaces(cgImage: CGImage) -> (count: Int, rects: [CGRect]) {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let observations = request.results ?? []
        let rects = observations.map(\.boundingBox)
        return (observations.count, rects)
    }

    // MARK: - Private

    private func runRequests(on cgImage: CGImage) -> VisionAnalysis {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Face rectangles + landmarks
        let faceRequest = VNDetectFaceLandmarksRequest()

        // Scene classification (uses built-in Vision model — no download needed)
        let classifyRequest = VNClassifyImageRequest()

        // OCR — fast path
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false

        // Animals
        let animalRequest = VNRecognizeAnimalsRequest()

        // Person segmentation (presence check only)
        let poseRequest = VNDetectHumanBodyPoseRequest()

        try? handler.perform([faceRequest, classifyRequest, textRequest, animalRequest, poseRequest])

        // Faces
        let faceObs = faceRequest.results ?? []
        let faceRects = faceObs.map(\.boundingBox)
        let landmarks = faceObs.compactMap(\.landmarks?.allPoints)

        // Scenes — keep top 5 with confidence > 0.3
        let sceneLabels: [(String, Float)] = (classifyRequest.results ?? [])
            .filter { $0.confidence > 0.3 }
            .prefix(5)
            .map { ($0.identifier, $0.confidence) }

        // Text
        let texts = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Animals
        let animals = (animalRequest.results ?? [])
            .flatMap { $0.labels }
            .filter { $0.confidence > 0.5 }
            .map(\.identifier)

        // Person presence
        let hasPerson = !(poseRequest.results ?? []).isEmpty

        return VisionAnalysis(
            faceCount: faceObs.count,
            faceRects: faceRects,
            faceLandmarks: landmarks,
            sceneLabels: sceneLabels,
            recognizedText: texts,
            animalLabels: animals,
            hasPersonSegmentation: hasPerson
        )
    }

    private func loadCGImage(for asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false  // don't block on iCloud for analysis
            options.isSynchronous = false
            let targetSize = CGSize(width: 512, height: 512)  // small enough for fast Vision
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}
