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
                    referenceStrip
                    actionButtons
                    statsRow
                    cardGrid
                }.padding()
            }
            bottomBar
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

    // MARK: - 子视图

    private var referenceStrip: some View {
        ReferenceStripView(
            images: vm.referenceImages,
            isEnabled: vm.useReferenceImages,
            onAdd: { showPhotoPicker = true },
            onRemove: { vm.removeReferenceImage(at: $0) },
            onClear: { vm.clearAllReferenceImages() }
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { vm.generateAllImages() } label: {
                    HStack { Image(systemName: "photo.on.rectangle.angled"); Text(vm.isLoading ? "生成中..." : "全部生成").font(.subheadline) }.frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(vm.isLoading)
                if vm.allSuccess { Button("完成") { vm.completeProject() }.buttonStyle(.bordered).controlSize(.small) }
            }
            HStack(spacing: 12) {
                Button { vm.generateTestImage(at: 0) } label: {
                    HStack { Image(systemName: "ladybug"); Text("测试第1张").font(.caption) }.frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).tint(.orange).disabled(vm.isLoading)
                Button { vm.downloadAllToAlbum() } label: {
                    HStack { Image(systemName: "square.and.arrow.down"); Text(vm.successCount > 0 ? "下载到相册(\(vm.successCount))" : "暂无可下载图片").font(.caption) }.frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).tint(.green).disabled(vm.successCount == 0)
            }
        }
    }

    private var statsRow: some View {
        VStack(spacing: 4) {
            HStack {
                if vm.allSuccess { Image(systemName: "checkmark.circle.fill").foregroundColor(.green); Text("全部完成（\(vm.successCount)/\(vm.imageCards.count)）").font(.caption).foregroundColor(.green) }
                else { Image(systemName: "photo").foregroundColor(.secondary); Text("\(vm.successCount)/\(vm.imageCards.count) 张成功").font(.caption).foregroundColor(.secondary) }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemGray6)).cornerRadius(8)
            if let m = vm.exportMessage { Text(m).font(.caption).foregroundColor(.green) }
            if let err = vm.errorMessage { Text(err).font(.caption).foregroundColor(.red).lineLimit(2) }
        }
    }

    private var cardGrid: some View {
        Group {
            if !vm.imageCards.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(vm.imageCards) { card in
                        ImageCardView(
                            card: card,
                            isGenerating: vm.currentGeneratingIndex == card.cardIndex,
                            onGenerate: { Task { await vm.generateImage(at: card.cardIndex) } },
                            onRegenerate: { vm.regenerateImage(at: card.cardIndex) },
                            onSaveToAlbum: { vm.saveToAlbum(at: card.cardIndex) }
                        )
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("\(vm.successCount)/\(vm.imageCards.count) 张").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("下载全部") { vm.downloadAllToAlbum() }.disabled(vm.successCount == 0).font(.caption).buttonStyle(.bordered).tint(.green).controlSize(.small)
            }.padding()
        }.background(Color(.systemBackground))
    }
}

// MARK: - 参考图条

struct ReferenceStripView: View {
    let images: [ReferenceImage]
    let isEnabled: Bool
    let onAdd: () -> Void
    let onRemove: (UUID) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled").foregroundColor(.blue)
                Text("参考图").font(.subheadline.bold())
                Spacer()
                Text("\(images.count)张").font(.caption).foregroundColor(.secondary)
                if isEnabled { Text("已启用").font(.caption2).foregroundColor(.green).padding(.horizontal,6).padding(.vertical,2).background(Color.green.opacity(0.1)).cornerRadius(4) }
            }
            if images.isEmpty {
                Button(action: onAdd) { HStack { Image(systemName: "plus.circle"); Text("从相册选择参考图（支持多张）").font(.subheadline) }.frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.bordered)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images) { ref in
                            if let d = try? Data(contentsOf: URL(fileURLWithPath: ref.localFilePath)), let ui = UIImage(data: d) {
                                Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 72).cornerRadius(6)
                                    .overlay(alignment: .topTrailing) {
                                        Button { onRemove(ref.id) } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.red).background(Color.white.clipShape(Circle())) }.buttonStyle(.plain).offset(x: 4, y: -4)
                                    }
                            }
                        }
                        Button(action: onAdd) { Image(systemName: "plus").font(.title2).foregroundColor(.blue).frame(width: 40, height: 40).background(Color.blue.opacity(0.1)).cornerRadius(8) }
                        Button("清空", action: onClear).font(.caption2).buttonStyle(.bordered).tint(.red).controlSize(.small)
                    }.padding(.vertical, 4)
                }.frame(height: 80)
            }
        }.padding(12).background(Color.blue.opacity(0.03)).cornerRadius(12)
    }
}
