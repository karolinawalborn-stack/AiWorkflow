import SwiftUI
#if os(iOS)
import UIKit
import Photos
#endif

///
/// 图片生成 ViewModel — 逐张生成 + 多格式适配
///
/// 🔍 排查指南：所有 guard/return 前都有打印，直接看日志就能知道断在哪一步。
///
@MainActor
final class ImageGenViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var progressText: String = ""
    @Published var errorMessage: String?
    @Published var exportMessage: String?
    @Published var currentGeneratingIndex: Int? = nil

    @Published var project: Project?
    private var store: ProjectStore?
    private var imageService: AIImageServiceProtocol?
    private var currentTask: Task<Void, Never>?

    /// 测试用固定 prompt（不依赖 promptCards）
    private let testPrompt = "A cute white round-headed cartoon character looking sad in dark blue-black room, single panel comic, emotional atmosphere, 3:4 ratio"

    // MARK: - 数据源

    var imageCards: [ImageCard] { project?.sortedImages ?? [] }
    var successCount: Int { imageCards.filter { $0.status == .success }.count }
    var allSuccess: Bool { !imageCards.isEmpty && imageCards.allSatisfy { $0.status == .success } }

    // MARK: - 设置

    func setup(store: ProjectStore, imageService: AIImageServiceProtocol, project: Project) {
        self.store = store
        self.imageService = imageService
        self.project = project

        let svcDesc = "\(type(of: imageService))"
        print("""
        📷 [ImageGen] ===== setup =====
           imageService 类型: \(svcDesc)
           imageCards: \(project.imageCards.count) 张
           promptCards 非空: \(project.promptCards.filter { !$0.promptText.isEmpty }.count) / \(project.promptCards.count)
        """)
        for (i, img) in project.sortedImages.enumerated() {
            print("   image[\(i)] status=\(img.status.rawValue) promptEmpty=\(img.promptText.isEmpty)")
        }
        for (i, p) in project.sortedPrompts.enumerated() {
            print("   prompt[\(i)] status=\(p.status.rawValue) textEmpty=\(p.promptText.isEmpty) text=「\(p.promptText.prefix(40))」")
        }
        print("📷 [ImageGen] ===== setup 完成 =====\n")
    }

    deinit {
        currentTask?.cancel()
    }

    // MARK: - ⭐️ 单张生成（核心链路）

    /// 生成第 N 张图片
    func generateImage(at index: Int) async {
        // ── 日志 ──
        let tag = "📷[\(index)]"
        print("\n\(tag) ===== 生成第\(index+1)张图片 =====")
        print("\(tag) 步骤1/6: 校验入参")

        // 校验1: index
        guard index >= 0 else {
            print("\(tag) ❌ 步骤1 失败: index=\(index) < 0，静默 return")
            return
        }

        // 校验2: imageService
        guard let imgSvc = imageService else {
            let msg = "图片服务未初始化（imageService 为 nil）"
            print("\(tag) ❌ 步骤2 失败: \(msg)")
            errorMessage = msg
            return
        }
        print("\(tag) ✅ 步骤2: imageService 已初始化")

        // 校验3: project
        guard var p = project else {
            let msg = "project 为 nil"
            print("\(tag) ❌ 步骤3 失败: \(msg)")
            errorMessage = msg
            return
        }
        print("\(tag) ✅ 步骤3: project 存在")

        // 校验4: imageCards 下标
        guard index < p.imageCards.count else {
            let msg = "imageCards 下标越界: index=\(index), count=\(p.imageCards.count)"
            print("\(tag) ❌ 步骤4 失败: \(msg)")
            errorMessage = msg
            return
        }
        print("\(tag) ✅ 步骤4: imageCards[\(index)] 存在")

        // 校验5: promptCards 数据源
        let promptText: String
        print("\(tag) 步骤5/6: 读取提示词数据源")
        print("\(tag)    promptCards.count=\(p.promptCards.count)")
        if index < p.promptCards.count {
            let cardPrompt = p.promptCards[index].promptText
            print("\(tag)    promptCards[\(index)].promptText.isEmpty=\(cardPrompt.isEmpty)")
            print("\(tag)    promptCards[\(index)].promptText=「\(cardPrompt.prefix(200))」")
            if !cardPrompt.isEmpty {
                promptText = cardPrompt
            } else {
                print("\(tag) ⚠️ promptText 为空，使用默认测试 prompt")
                promptText = testPrompt
            }
        } else {
            print("\(tag) ⚠️ index(\(index)) >= promptCards.count(\(p.promptCards.count))，使用默认测试 prompt")
            promptText = testPrompt
        }
        print("\(tag) ✅ 步骤5: 最终使用的 promptText 前300字=「\(promptText.prefix(300))」")

        let size = p.ratio == "3:4" ? "1024x1792" : "1024x1024"
        print("\(tag) 尺寸: \(size)")

        // ── 所有校验通过，即将发请求 ──
        print("\(tag) ===== 全部校验通过，即将发起 API 请求 ===== ")
        print("\(tag) 当前时间戳: \(Date())")

        // 只有在这里才标记 generating（之前失败不会卡在 generating 状态）
        currentGeneratingIndex = index
        p.imageCards[index].status = .generating
        p.imageCards[index].promptText = promptText
        p.imageCards[index].errorMessage = nil
        project = p

        let start = Date()

        do {
            // ── 真正调用 image service ──
            print("\(tag) ⏳ 正在调用 imgSvc.generateImage()...")
            print("\(tag)       prompt.prefix(200)=\(promptText.prefix(200))")
            print("\(tag)       size=\(size) n=1")
            let results = try await imgSvc.generateImage(prompt: promptText, size: size, n: 1)

            // ── API 返回 ──
            try Task.checkCancellation()
            let elapsed = Date().timeIntervalSince(start)
            print("\(tag) ✅ imgSvc.generateImage() 返回 (\(String(format: "%.1f", elapsed))s)")
            print("\(tag)    results.count=\(results.count)")

            guard let result = results.first else {
                print("\(tag) ❌ results 为空数组")
                setImageFailed(index, status: .parseFailed, error: "API 返回空结果")
                currentGeneratingIndex = nil
                return
            }
            print("\(tag)    result.imageData 非空=\(result.imageData != nil)")
            print("\(tag)    result.imageURL=\(result.imageURL ?? "nil")")
            print("\(tag)    result.revisedPrompt.prefix(100)=\(result.revisedPrompt?.prefix(100) ?? "nil")")

            // 解析结果
            try await processImageResult(index: index, result: result, size: size)

        } catch is CancellationError {
            print("\(tag) ⏹ 请求被取消")
            setImageFailed(index, status: .failed, error: "请求被取消")
            currentGeneratingIndex = nil
        } catch {
            print("\(tag) ❌ 请求异常: \(error.localizedDescription)")
            let ns = error as NSError
            print("\(tag)    domain=\(ns.domain) code=\(ns.code)")
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorCancelled:
                    print("\(tag)    = NSURLErrorCancelled (后台取消)")
                    setImageFailed(index, status: .failed, error: "请求被中断（后台）")
                case NSURLErrorBadURL:
                    print("\(tag)    = NSURLErrorBadURL (URL 无效)")
                    setImageFailed(index, status: .failed, error: "图片服务 URL 配置无效")
                case NSURLErrorUnsupportedURL:
                    print("\(tag)    = NSURLErrorUnsupportedURL")
                    setImageFailed(index, status: .failed, error: "不支持的 URL 格式")
                case NSURLErrorCannotConnectToHost:
                    print("\(tag)    = NSURLErrorCannotConnectToHost (无法连接)")
                    setImageFailed(index, status: .failed, error: "无法连接到图片服务")
                default:
                    print("\(tag)    = NSURLError.\(ns.code)")
                    setImageFailed(index, status: .failed, error: "网络错误: \(ns.localizedDescription)")
                }
            } else {
                setImageFailed(index, status: .failed, error: error.localizedDescription)
            }
            currentGeneratingIndex = nil
        }
    }

    // MARK: - 处理图片结果

    private func processImageResult(index: Int, result: ImageGenerationResult, size: String) async throws {
        let tag = "📷[\(index)]"
        print("\(tag) processImageResult: imageData=\(result.imageData?.count ?? 0)bytes, imageURL=\(result.imageURL ?? "nil")")

        // 方案一：有二进制数据
        if let imageData = result.imageData, !imageData.isEmpty {
            print("\(tag) ✔ 格式=二进制数据, \(imageData.count) bytes")
            try await saveImageLocally(index: index, imageData: imageData, result: result)
            return
        }

        // 方案二：有 URL → 下载
        if let urlStr = result.imageURL, let url = URL(string: urlStr) {
            print("\(tag) ✔ 格式=URL, \(urlStr)")
            print("\(tag) ⏳ 开始下载...")
            do {
                let request = URLRequest(url: url, timeoutInterval: 30)
                let (data, resp) = try await URLSession.shared.data(for: request)
                let httpCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard !data.isEmpty else {
                    print("\(tag) ❌ 下载返回空数据, HTTP \(httpCode)")
                    setImageFailed(index, status: .parseFailed, error: "图片 URL 下载返回空数据 (HTTP \(httpCode))", rawResponse: urlStr)
                    return
                }
                print("\(tag) ✔ 下载成功: \(data.count) bytes, HTTP \(httpCode)")
                try await saveImageLocally(index: index, imageData: data, result: result)
            } catch {
                print("\(tag) ❌ URL 下载异常: \(error.localizedDescription)")
                setImageFailed(index, status: .parseFailed, error: "图片 URL 下载失败: \(error.localizedDescription)", rawResponse: urlStr)
            }
            return
        }

        // 方案三：无 data 无 url → 解析失败
        print("\(tag) ❌ 无法识别图片返回格式: 无 data 无 url")
        setImageFailed(index, status: .parseFailed, error: "API 返回成功但无法识别图片数据格式", rawResponse: result.revisedPrompt ?? "未知格式")
    }

    // MARK: - 本地保存

    private func saveImageLocally(index: Int, imageData: Data, result: ImageGenerationResult) async throws {
        let tag = "📷[\(index)]"
        print("\(tag) saveImageLocally: \(imageData.count) bytes")

        #if os(iOS)
        guard UIImage(data: imageData) != nil else {
            print("\(tag) ❌ UIImage 解码失败")
            setImageFailed(index, status: .parseFailed, error: "图片数据无法解码为 UIImage")
            return
        }
        print("\(tag) ✅ UIImage 解码成功")
        #endif

        let fileName = "img_\(project?.id.uuidString.prefix(8) ?? "x")_\(index).jpg"
        guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("\(tag) ❌ 无法获取文档目录")
            setImageFailed(index, status: .saveFailed, error: "无法获取文档目录")
            return
        }

        let fileURL = docDir.appendingPathComponent(fileName)
        do {
            try imageData.write(to: fileURL)
            print("\(tag) ✅ 写入本地文件: \(fileURL.path)")
        } catch {
            print("\(tag) ❌ 写入文件失败: \(error.localizedDescription)")
            setImageFailed(index, status: .saveFailed, error: "本地文件写入失败: \(error.localizedDescription)")
            return
        }

        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = .success
        p.imageCards[index].imageBase64 = imageData.base64EncodedString()
        p.imageCards[index].localFilePath = fileURL.path
        p.imageCards[index].imageURL = result.imageURL
        p.imageCards[index].rawResponse = result.revisedPrompt ?? ""
        p.imageCards[index].errorMessage = nil
        if p.imageCards.allSatisfy({ $0.status == .success }) { p.status = .imagesReady }
        p.updatedAt = Date()
        store?.upsert(p)
        project = p

        currentGeneratingIndex = nil
        print("\(tag) ✅ 全部完成！文件: \(fileURL.lastPathComponent)")
    }

    private func setImageFailed(_ index: Int, status: ImageStatus, error: String, rawResponse: String = "") {
        guard var p = project, index < p.imageCards.count else {
            print("📷[\(index)] setImageFailed: project 或 index 无效，无法写入")
            return
        }
        p.imageCards[index].status = status
        p.imageCards[index].errorMessage = error
        if !rawResponse.isEmpty { p.imageCards[index].rawResponse = rawResponse }
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
        print("📷[\(index)] ❌ 状态=\(status.rawValue) 错误=\(error)")
    }

    // MARK: - ⭐️ 测试单张（固定 prompt，绕过所有数据源校验）

    /// 直接使用固定测试 prompt 生成第 index 张图
    /// 用于验证"图片请求链路本身是否能发出去"
    func generateTestImage(at index: Int) {
        print("\n🧪 [ImageGen] ===== 测试模式：第\(index+1)张 =====")
        print("🧪 使用固定测试 prompt，不依赖 promptCards")

        guard var p = project, index < p.imageCards.count else {
            print("🧪 ❌ 项目或下标无效")
            return
        }

        // 直接写入测试 prompt
        print("🧪 测试 prompt: 「\(testPrompt)」")
        p.imageCards[index].promptText = testPrompt
        p.imageCards[index].errorMessage = nil
        project = p
        store?.upsert(p)

        // 走正常生成流程（所有校验会通过，因为 promptText 已写入）
        Task {
            await generateImage(at: index)
            if let np = project { store?.upsert(np) }
        }
    }

    // MARK: - 批量生成

    func generateAllImages() {
        print("\n🔵 [ImageGen] ===== 开始批量生成 =====")

        guard let p = project else {
            print("🔵 ❌ project 为空")
            errorMessage = "项目未加载"
            return
        }

        // 重载
        let freshProject: Project
        if let s = store, let reloaded = s.project(id: p.id) {
            freshProject = reloaded
            project = reloaded
            print("🔵 从 store 重载项目成功")
        } else {
            freshProject = p
            print("🔵 使用当前 project（未重载）")
        }

        let toGenerate = freshProject.imageCards.indices.filter { idx in
            freshProject.imageCards[idx].status != .success
        }

        print("🔵 待生成: \(toGenerate.count) 张")
        if toGenerate.isEmpty {
            print("🔵 所有图片已生成，无需操作")
            return
        }

        // 取消旧任务
        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        progressText = ""
        currentGeneratingIndex = nil

        // 重置待生成卡片为 idle
        var np = freshProject
        for idx in toGenerate where idx < np.imageCards.count {
            np.imageCards[idx].status = .idle
            np.imageCards[idx].errorMessage = nil
        }
        project = np
        store?.upsert(np)

        currentTask = Task {
            for (loopIdx, idx) in toGenerate.enumerated() {
                if Task.isCancelled {
                    print("🔵 ⏹ Task 被取消，中断批量")
                    break
                }
                progressText = "生成第\(loopIdx+1)/\(toGenerate.count)张..."
                print("🔵 循环: loopIdx=\(loopIdx) cardIdx=\(idx) progressText=\(progressText)")
                await generateImage(at: idx)
                if let np2 = project { store?.upsert(np2) }
            }
            isLoading = false
            currentGeneratingIndex = nil
            let total = imageCards.count
            let done = successCount
            progressText = done == total ? "全部完成" : "\(done)/\(total) 张完成"
            print("🔵 [ImageGen] 批量完成: \(done)/\(total)")
        }
    }

    // MARK: - 重新生成单张

    func regenerateImage(at index: Int) {
        print("\n🔄 [ImageGen] ===== 重新生成第\(index+1)张 =====")
        guard let p = project, index < p.imageCards.count else {
            print("🔄 ❌ 项目或下标无效")
            return
        }
        var np = p
        np.imageCards[index].status = .idle
        np.imageCards[index].errorMessage = nil
        np.imageCards[index].imageBase64 = nil
        np.imageCards[index].localFilePath = nil
        project = np
        store?.upsert(np)

        Task {
            await generateImage(at: index)
            if let np2 = project { store?.upsert(np2) }
        }
    }

    // MARK: - 相册 & 完成

    func saveToAlbum(at index: Int) {
        #if os(iOS)
        guard index < imageCards.count, imageCards[index].status == .success,
              let data = imageCards[index].decodedImageData,
              let ui = UIImage(data: data) else {
            errorMessage = "图片不存在或未生成"
            return
        }
        PHPhotoLibrary.requestAuthorization { s in
            guard s == .authorized || s == .limited else {
                DispatchQueue.main.async { self.errorMessage = "无相册权限" }
                return
            }
            PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: ui) } completionHandler: { ok, err in
                DispatchQueue.main.async {
                    if ok { self.exportMessage = "已保存" }
                    else { self.errorMessage = "保存失败: \(err?.localizedDescription ?? "")" }
                }
            }
        }
        #endif
    }

    func completeProject() {
        guard var p = project else { return }
        p.status = .completed
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
    }
}
