import SwiftUI

struct HistoryListView: View {
    @Environment(\.projectStore) private var store
    @StateObject private var vm = HistoryViewModel()
    @State private var detail: Project?

    var body: some View {
        NavigationStack {
            Group {
                if vm.projects.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "clock.arrow.circlepath").font(.system(size: 48)).foregroundColor(.secondary); Text("暂无历史项目").font(.title2); Text("完成的项目将出现在这里").foregroundColor(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.groupedByStatus, id: \.0) { status, list in
                            Section {
                                ForEach(list) { p in
                                    Button { detail = p } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack { Text(p.name).font(.headline); Spacer(); Text(p.status.displayName).font(.caption).padding(.horizontal,6).padding(.vertical,2).background(color(p.status).opacity(0.15)).foregroundColor(color(p.status)).cornerRadius(4) }
                                            HStack(spacing: 8) { Label(p.category, systemImage: "tag"); Label("\(p.imageCount)张", systemImage: "photo"); Label(p.ratio, systemImage: "rectangle.ratio.3.to.4") }.font(.caption).foregroundColor(.secondary)
                                            ProgressView(value: p.status.progressValue).tint(color(p.status))
                                        }.padding(.vertical, 4)
                                    }.swipeActions(edge: .trailing) { Button("删除", role: .destructive) { vm.deleteById(p.id) } }
                                }
                            } header: { Text(status.displayName).foregroundColor(.secondary) }
                        }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle("历史项目").searchable(text: $vm.searchText, prompt: "搜索...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("全部") { vm.filterStatus = nil; vm.reload() }
                        ForEach(ProjectStatus.allCases, id: \.self) { s in Button(s.displayName) { vm.filterStatus = s; vm.reload() } }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .sheet(item: $detail) { p in DetailView(project: p) }
            .onAppear { vm.setup(store: store) }
        }
    }

    func color(_ s: ProjectStatus) -> Color {
        switch s { case .draft: return .gray; case .topicsReady, .topicSelected: return .blue; case .copyReady: return .purple; case .promptsReady: return .orange; case .imagesReady: return .green; case .completed: return .green }
    }
}

struct DetailView: View {
    let project: Project
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack { Text("名称"); Spacer(); Text(project.name).foregroundColor(.secondary) }
                    HStack { Text("赛道"); Spacer(); Text(project.category).foregroundColor(.secondary) }
                    HStack { Text("状态"); Spacer(); Text(project.status.displayName).foregroundColor(.secondary) }
                    HStack { Text("图数"); Spacer(); Text("\(project.imageCount)张").foregroundColor(.secondary) }
                    HStack { Text("比例"); Spacer(); Text(project.ratio).foregroundColor(.secondary) }
                } header: { Text("项目信息").foregroundColor(.secondary) }

                if !project.sortedTopics.isEmpty {
                    Section { ForEach(project.sortedTopics) { t in VStack(alignment: .leading) { Text(t.title).font(.subheadline); Text(t.topicDescription).font(.caption).foregroundColor(.secondary) } } }
                    header: { Text("选题").foregroundColor(.secondary) }
                }

                let cards = project.sortedCopyCards.filter { !$0.isEmpty }
                if !cards.isEmpty {
                    Section { ForEach(cards) { c in VStack(alignment: .leading) { Text("图\(c.cardIndex+1)：\(c.topText)").font(.subheadline); Text(c.bottomText).font(.caption).foregroundColor(.secondary) } } }
                    header: { Text("文案").foregroundColor(.secondary) }
                }

                let prompts = project.sortedPrompts.filter { !$0.promptText.isEmpty }
                if !prompts.isEmpty {
                    Section { ForEach(prompts) { p in VStack(alignment: .leading) { Text("图\(p.cardIndex+1)").font(.caption).foregroundColor(.secondary); Text(p.promptText).font(.caption) } } }
                    header: { Text("提示词").foregroundColor(.secondary) }
                }

                let imgs = project.sortedImages.filter { $0.isGenerated }
                if !imgs.isEmpty {
                    Section {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(imgs) { img in
                                if let data = img.imageData, let ui = UIImage(data: data) { Image(uiImage: ui).resizable().aspectRatio(3/4, contentMode: .fit).cornerRadius(8) }
                                else { Rectangle().aspectRatio(3/4, contentMode: .fit).foregroundColor(.gray).overlay(Text("无图").font(.caption)).cornerRadius(8) }
                            }
                        }
                    } header: { Text("图片").foregroundColor(.secondary) }
                }
            }
            .navigationTitle(project.name).navigationBarTitleDisplayMode(.inline)
        }
    }
}

