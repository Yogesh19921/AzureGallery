import SwiftUI
import Photos

struct PhotoDetailView: View {
    let assets: [PHAsset]
    @State var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(assets.enumerated()), id: \.offset) { index, asset in
                AssetDetailPage(asset: asset)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(.black)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding()
            }
        }
    }
}

private struct AssetDetailPage: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.black)
        .onAppear { loadImage() }
    }

    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let size = CGSize(width: UIScreen.main.bounds.width * UIScreen.main.scale,
                          height: UIScreen.main.bounds.height * UIScreen.main.scale)
        PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { result, _ in
            if let result { image = result }
        }
    }
}
