import SwiftUI

struct ImageGenView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.imageService) private var imageService
    @StateObject private var vm = ImageGenViewModel()
    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let p = vm.project { ProgressHeader(title: p.name, step: 4, total: 4, tint: .green) }

                    HStack(spacing: 12) {
                        Button { vm.generateAllImages() } label: { HStack { Image(systemName: "photo.on.rectangle.angled"); Text(vm.isGeneratingAll ? "生成中..." : "全部生成") }.frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).disabled(vm.isGeneratingAll)
                        if vm.allGenerated { Button("完成") { vm.completeProject() }.buttonStyle(.bordered) }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(Array(vm.images.enumerated()), id: \.offset) { idx, img in
                            VStack(spacing: 8) {
                                ZStack {
                                    if let data = img.imageData, let ui = UIImage(data: data) {
                                        Image(uiImage: ui).resizable().aspectRatio(3/4, contentMode: .fit).cornerRadius(8)
                                    } else {
                                        Rectangle().aspectRatio(3/4, contentMode: .fit).foregroundColor(Color(.systemGray5)).cornerRadius(8)
                                            .overlay {
                                                if vm.generatingIndex == idx { VStack(spacing: 8) { ProgressView(); Text("生成中...").font(.caption) }.foregroundColor(.secondary) }
                                                else if img.isGenerated { VStack(spacing: 4) { Image(systemName: "photo.badge.exclamationmark"); Text("加载失败").font(.caption) }.foregroundColor(.secondary) }
                                                else { VStack(spacing: 4) { Image(systemName: "photo").font(.title2); Text("未生成").font(.caption) }.foregroundColor(.secondary) }
                                            }
                                    }
                                    if img.isGenerated { VStack { HStack { Spacer(); Text("图\(idx+1)").font(.caption2).padding(.horizontal,6).padding(.vertical,3).background(Color.black.opacity(0.6)).foregroundColor(.white).cornerRadius(4).padding(4) }; Spacer() } }
                                }
                                HStack(spacing: 8) {
                                    if img.isGenerated {
                                        Button { vm.saveToAlbum(at: idx) } label: { Image(systemName: "square.and.arrow.down").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                                        Button { Task { await vm.generateImage(at: idx) } } label: { Image(systemName: "arrow.clockwise").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                                    } else {
                                        Button { Task { await vm.generateImage(at: idx) } } label: { HStack { Image(systemName: "wand.and.stars"); Text("生成") }.font(.caption).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.small).disabled(vm.generatingIndex == idx)
                                    }
                                }
                            }.padding(8).background(Color(.systemGray6)).cornerRadius(12)
                        }
                    }
                }.padding()
            }
            VStack(spacing: 0) { Divider(); HStack { Text("\(vm.generatedCount)/\(vm.images.count)张").font(.caption).foregroundColor(.secondary); Spacer(); if let m = vm.exportMessage { Text(m).font(.caption).foregroundColor(.green) } }.padding() }.background(Color(.systemBackground))
        }
        .navigationTitle("出图").navigationBarTitleDisplayMode(.inline)
        .overlay {
            if vm.isGeneratingAll {
                Color.black.opacity(0.3).ignoresSafeArea().overlay { VStack(spacing: 16) { ProgressView().scaleEffect(1.5).tint(.white); Text(vm.progressText).foregroundColor(.white).font(.headline) }.padding(32).background(Color(.systemGray2).opacity(0.8)).cornerRadius(16) }
            }
        }
        .onAppear { if let p = store.project(id: projectID) { vm.setup(store: store, imageService: imageService, project: p) } }
    }
}
