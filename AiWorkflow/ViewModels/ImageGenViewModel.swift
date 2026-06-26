import SwiftUI
#if os(iOS)
import UIKit
import Photos
#endif

@MainActor
final class ImageGenViewModel: ObservableObject {
    @Published var images: [GeneratedImageItem] = []
    @Published var generatingIndex: Int?
    @Published var isGeneratingAll = false
    @Published var progressText: String = ""
    @Published var errorMessage: String?
    @Published var exportMessage: String?

    var project: Project?
    private var store: ProjectStore?
    private var imageService: AIImageServiceProtocol?

    func setup(store: ProjectStore, imageService: AIImageServiceProtocol, project: Project) {
        self.store = store; self.imageService = imageService; self.project = project
        self.images = project.sortedImages
    }

    func generateImage(at index: Int) async {
        guard index < images.count, let imgSvc = imageService else { return }
        generatingIndex = index; errorMessage = nil

        let promptText: String
        if index < (project?.promptCards.count ?? 0), let p = project?.sortedPrompts, index < p.count, !p[index].prompt.isEmpty {
            promptText = p[index].prompt
        } else {
            promptText = "A cute white round-headed cartoon character, dark blue-black background, dual-panel comic layout with captions, oppressive emotional atmosphere, 3:4 ratio"
        }
        let size = project?.ratio == "3:4" ? "1024x1792" : "1024x1024"

        do {
            let results = try await imgSvc.generateImage(prompt: promptText, size: size, n: 1)
            guard let result = results.first else { throw NetworkError.noData }

            var item = images[index]
            item.imageData = result.data
            item.usedPrompt = result.revisedPrompt ?? promptText
            item.isGenerated = true
            images[index] = item

            var p = project!; p.imageItems[index] = item
            if p.imageItems.allSatisfy({ $0.isGenerated }) { p.status = .imagesReady }
            store?.upsert(p); project = p
            generatingIndex = nil
        } catch {
            errorMessage = "图\(index+1)失败：\(error.localizedDescription)"; generatingIndex = nil
        }
    }

    func generateAllImages() {
        isGeneratingAll = true; errorMessage = nil
        Task {
            for index in 0..<images.count {
                if images[index].isGenerated { continue }
                progressText = "生成第\(index+1)/\(images.count)张..."
                await generateImage(at: index)
                if errorMessage != nil { break }
            }
            isGeneratingAll = false; progressText = "全部完成"
        }
    }

    func saveToAlbum(at index: Int) {
        #if os(iOS)
        guard index < images.count, images[index].isGenerated, let data = images[index].imageData, let ui = UIImage(data: data) else {
            errorMessage = "图片不存在"; return
        }
        PHPhotoLibrary.requestAuthorization { s in
            guard s == .authorized || s == .limited else { DispatchQueue.main.async { self.errorMessage = "无相册权限" }; return }
            PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: ui) } completionHandler: { ok, err in
                DispatchQueue.main.async { if ok { self.exportMessage = "已保存" } else { self.errorMessage = "保存失败" } }
            }
        }
        #endif
    }

    func completeProject() {
        var p = project!; p.status = .completed; p.updatedAt = Date(); store?.upsert(p); project = p
    }

    var generatedCount: Int { images.filter { $0.isGenerated }.count }
    var allGenerated: Bool { images.allSatisfy { $0.isGenerated } }
}
