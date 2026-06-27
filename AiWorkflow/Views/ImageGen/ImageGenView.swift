import SwiftUI
#if os(iOS)
import UIKit
import PhotosUI
#endif

struct ImageGenView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.imageService) private var imageService
    @StateObject private var vm = ImageGenViewModel()
    @State private var showPhotoPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let p = vm.project { ProgressHeader(title: p.name, step: 4, total: 4, tint: .green) }

                    // ── 参考图区域（多张） ──
                    referenceSection

                    // ── 操作按钮 ──
                    HStack(spacing: 12) {
                        Button { vm.generateAllImages() } label: {
                            HStack { Image(systemName: "photo.on.rectangle.angled"); Text(vm.isLoading ? "生成中..." : "全部生成") }.frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).disabled(vm.isLoading)
                        if vm.allSuccess { Button("完成") { vm.completeProject() }.buttonStyle(.bordered) }
                    }

                    HStack(spacing: 12) {
                        Button { vm.generateTestImage(at: 0) } label: {
                            HStack { Image(systemName: "ladybug"); Text("测试第1张").font(.caption) }.frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(.orange).disabled(vm.isLoading)
                        Button { vm.downloadAllToAlbum() } label: {
                                HStack { Image(systemName: "square.and.arrow.down"); Text(vm.successCount > 0 ? "下载到相册(\(vm.successCount))" : "暂无可下载图片").font(.caption) }.frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered).tint(.green).disabled(vm.successCount == 0)
                    }

                    // ── 统计 ──
                    HStack {
                        if vm.allSuccess { Image(systemName: "checkmark.circle.fill").foregroundColor(.green); Text("全部完成（\(vm.successCount)/\(vm.imageCards.count)）").font(.caption).foregroundColor(.green) }
                        else { Image(systemName: "photo").foregroundColor(.secondary); Text("\(vm.successCount)/\(vm.imageCards.count) 张成功").font(.caption).foregroundColor(.secondary) }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemGray6)).cornerRadius(8)

                    if let m = vm.exportMessage { Text(m).font(.caption).foregroundColor(.green) }
                    if let err = vm.errorMessage { Text(err).font(.caption).foregroundColor(.red).lineLimit(3) }

                    // ── 卡片 ──
                    if !vm.imageCards.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(vm.imageCards) { card in ImageCardRowView(card: card, vm: vm) }
                        }
                    }
                }.padding()
            }

            // ── 底部 ──
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text("\(vm.successCount)/\(vm.imageCards.count) 张").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("下载全部") { vm.downloadAllToAlbum() }.disabled(vm.successCount == 0).font(.caption).buttonStyle(.bordered).tint(.green).controlSize(.small) }
                }.padding()
            }.background(Color(.systemBackground))
        }
        .navigationTitle("出图").navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems, maxSelectionCount: 9, matching: .images)
        .onChange(of: photoPickerItems) { items in
            guard !items.isEmpty else { return }
            Task {
                var urls: [URL] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ref_\(UUID().uuidString.prefix(8)).jpg")
                        try? data.write(to: tmp); urls.append(tmp)
                    }
                }
                await MainActor.run { vm.addReferenceImages(from: urls); photoPickerItems = [] }
            }
        }
        .onAppear { if let p = store.project(id: projectID) { vm.setup(store: store, imageService: imageService, project: p) } }
    }

    // MARK: - 参考图（多张）

    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled").foregroundColor(.blue)
                Text("参考图").font(.subheadline.bold())
                Spacer()
                Text("\(vm.referenceImages.count)张").font(.caption).foregroundColor(.secondary)
                if vm.useReferenceImages { Text("已启用").font(.caption2).foregroundColor(.green).padding(.horizontal,6).padding(.vertical,2).background(Color.green.opacity(0.1)).cornerRadius(4) }
            }
            if vm.referenceImages.isEmpty {
                Button { showPhotoPicker = true } label: {
                    HStack { Image(systemName: "plus.circle"); Text("从相册选择参考图（支持多张）").font(.subheadline) }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.bordered)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.referenceImages) { ref in
                            if let d = try? Data(contentsOf: URL(fileURLWithPath: ref.localFilePath)), let ui = UIImage(data: d) {
                                Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 72).cornerRadius(6)
                                    .overlay(alignment: .topTrailing) {
                                        Button { vm.removeReferenceImage(at: ref.id) } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.red).background(Color.white.clipShape(Circle())) }.buttonStyle(.plain).offset(x: 4, y: -4)
                                    }
                            }
                        }
                        Button { showPhotoPicker = true } label: { Image(systemName: "plus").font(.title2).foregroundColor(.blue).frame(width: 40, height: 40).background(Color.blue.opacity(0.1)).cornerRadius(8) }
                        Button("清空") { vm.clearAllReferenceImages() }.font(.caption2).buttonStyle(.bordered).tint(.red).controlSize(.small)
                    }.padding(.vertical, 4)
                }.frame(height: 80)
            }
        }.padding(12).background(Color.blue.opacity(0.03)).cornerRadius(12)
    }

// MARK: - 单张卡片

struct ImageCardRowView: View {
    let card: ImageCard
    @ObservedObject var vm: ImageGenViewModel
    @State private var showDebug = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let data = card.decodedImageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().aspectRatio(3/4, contentMode: .fit).cornerRadius(8)
                } else {
                    Rectangle().aspectRatio(3/4, contentMode: .fit).foregroundColor(bgColor).cornerRadius(8).overlay { statusOverlay }
                }
                if card.status == .success {
                    VStack { HStack { Spacer(); Text("图\(card.cardIndex+1)").font(.caption2).padding(.horizontal,6).padding(.vertical,3).background(Color.black.opacity(0.6)).foregroundColor(.white).cornerRadius(4).padding(4) }; Spacer() }
                }
            }

            Text(statusLabel).font(.caption2).foregroundColor(statusColor)

            if let tid = card.taskId, card.status != .success {
                Text("ID: \(tid.prefix(12))...").font(.system(size: 8)).foregroundColor(.secondary)
            }
            if !card.efsIds.isEmpty, card.status != .success {
                Text("efs: \(card.efsIds.joined(separator: ",").prefix(20))...").font(.system(size: 8)).foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                if card.status == .success {
                    Button { vm.saveToAlbum(at: card.cardIndex) } label: { Image(systemName: "square.and.arrow.down").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                    Button { vm.regenerateImage(at: card.cardIndex) } label: { Image(systemName: "arrow.clockwise").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                } else if card.status == .idle || card.status == .failed || card.status == .timeout {
                    Button { vm.regenerateImage(at: card.cardIndex) } label: { HStack { Image(systemName: "wand.and.stars"); Text("生成/重试").font(.caption) }.frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    ProgressView().scaleEffect(0.6); Text("处理中...").font(.caption2).foregroundColor(.secondary)
                }
            }

            if card.status != .idle {
                Button { withAnimation { showDebug.toggle() } } label: { HStack { Image(systemName: showDebug ? "chevron.down" : "chevron.right"); Text("调试").font(.caption2) }.foregroundColor(.secondary) }
                if showDebug {
                    VStack(alignment: .leading, spacing: 2) {
                        if let e = card.errorMessage { Text(e).font(.system(size: 8)).foregroundColor(.red) }
                        if let t = card.taskId { Text("task: \(t)").font(.system(size: 8)).foregroundColor(.secondary) }
                        if !card.efsIds.isEmpty { Text("efs: \(card.efsIds.joined(separator: ","))").font(.system(size: 8)).foregroundColor(.secondary) }
                        if !card.rawSubmitResponse.isEmpty { Text("提交: \(card.rawSubmitResponse.prefix(100))").font(.system(size: 7)).foregroundColor(.secondary) }
                        if !card.rawQueryResponse.isEmpty { Text("查询: \(card.rawQueryResponse.prefix(100))").font(.system(size: 7)).foregroundColor(.secondary) }
                        if let p = card.localFilePath { Text("路径: \(p)").font(.system(size: 7)).foregroundColor(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4).background(Color(.systemGray6)).cornerRadius(4)
                }
            }
        }
        .padding(6).background(cardBackground).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 0.5))
    }

    private var statusLabel: String {
        switch card.status {
        case .idle:"未生成"; case .generating:"生成中..."; case .success:"✅ 成功"; case .failed:"❌ 失败"
        case .parseFailed:"⚠️ 解析失败"; case .taskAccepted:"📋 已接收"; case .polling:"🔄 查询中"
        case .downloading:"⬇️ 下载中"; case .timeout:"⏰ 超时"; case .saveFailed:"⚠️ 保存失败"
        case .binaryImageReceived:"📷 已收到"; case .cancelled:"🚫 取消"
        }
    }
    private var statusColor: Color {
        switch card.status {
        case .idle:.secondary; case .generating:.orange; case .success:.green; case .failed:.red
        case .parseFailed:.orange; case .taskAccepted:.purple; case .polling:.orange
        case .downloading:.blue; case .timeout:.red; case .saveFailed:.orange; case .binaryImageReceived:.blue; case .cancelled:.gray
        }
    }
    private var bgColor: Color {
        if card.status == .failed||card.status == .timeout {return Color.red.opacity(0.08)}
        return Color(.systemGray5)
    }
    private var cardBackground: Color {
        if card.status == .success {return Color.green.opacity(0.04)}
        if card.status == .failed||card.status == .timeout {return Color.red.opacity(0.03)}
        return Color(.systemGray6)
    }
    private var borderColor: Color {
        if card.status == .success {return Color.green.opacity(0.2)}
        return .clear
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if card.status == .generating||card.status == .polling||card.status == .taskAccepted {
            VStack(spacing:6){ProgressView().scaleEffect(0.8);Text(statusLabel).font(.caption2)}.foregroundColor(.secondary)
        } else if card.status == .failed||card.status == .timeout {
            VStack(spacing:4){Image(systemName:"exclamationmark.triangle").font(.title2);Text(statusLabel).font(.caption2);if let e=card.errorMessage{Text(e).font(.caption2).foregroundColor(.secondary).lineLimit(2).multilineTextAlignment(.center)}}.foregroundColor(statusColor).padding(4)
        } else if card.status == .idle {
            VStack(spacing:4){Image(systemName:"photo").font(.title2);Text("未生成").font(.caption)}.foregroundColor(.secondary)
        }
    }
}
