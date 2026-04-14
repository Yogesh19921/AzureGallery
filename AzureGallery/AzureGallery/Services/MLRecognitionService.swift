import Foundation
import CoreML
import Vision
import Photos
import UIKit

// MLRecognitionService manages custom Core ML model inference.
// Out of the box it runs with no model — all Vision built-ins still work.
// To enable custom face recognition:
//   1. Train a model in CreateML (Image Classifier or feature extractor)
//   2. Drag the .mlmodel into Xcode
//   3. Set modelName below to the compiled model filename (without extension)

private let modelName: String? = nil   // e.g. "FaceRecognizer"

struct RecognitionResult: Sendable {
    let label: String
    let confidence: Float
}

final class MLRecognitionService {
    static let shared = MLRecognitionService()

    private var model: VNCoreMLModel?
    var isModelAvailable: Bool { model != nil }

    private init() {
        model = loadModel()
    }

    // Classify a PHAsset using the bundled Core ML model.
    // Returns empty array if no model is loaded.
    func classify(asset: PHAsset) async -> [RecognitionResult] {
        guard let model else { return [] }
        guard let cgImage = await loadCGImage(for: asset) else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNCoreMLRequest(model: model)
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                let results = (request.results as? [VNClassificationObservation] ?? [])
                    .filter { $0.confidence > 0.3 }
                    .prefix(5)
                    .map { RecognitionResult(label: $0.identifier, confidence: $0.confidence) }
                continuation.resume(returning: Array(results))
            }
        }
    }

    // Face embedding comparison — returns cosine similarity 0..1.
    // Requires a feature-vector Core ML model (not a classifier).
    func similarity(between imageA: CGImage, and imageB: CGImage) async -> Float {
        // Placeholder: when a feature-extraction model is loaded, compute embeddings
        // and return cosine similarity. Without a model, falls back to 0.
        guard model != nil else { return 0 }
        return 0  // implement when model is wired
    }

    // MARK: - Private

    private func loadModel() -> VNCoreMLModel? {
        guard let name = modelName else { return nil }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            print("MLRecognitionService: model '\(name).mlmodelc' not found in bundle")
            return nil
        }
        guard let mlModel = try? MLModel(contentsOf: url),
              let vnModel = try? VNCoreMLModel(for: mlModel) else { return nil }
        return vnModel
    }

    private func loadCGImage(for asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 299, height: 299),  // common input size for CoreML classifiers
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}
