import SwiftUI

struct HomeView: View {
    @Environment(\.projectStore) private var store
    @StateObject private var vm = HomeViewModel()
    @State private var settingsSheet = false
    @State private var topicProjectID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // ── 三大入口 ──
                    VStack(spacing: 16) {
                        Button {
                            let p = Project(name: "新创作")
                            store?.upsert(p)
                            topicProjectID = p.id
                        } label: {
                            HStack {
                                Image(systemName: "sparkles.rectangle.stack").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("生成选题").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("基于默认模板，AI 自动生成 6 个双格漫画选题").font(.caption).foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(20)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)

                        Button {
                            // 历史项目
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("历史记录").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("查看已完成的 \(vm.projects.count) 个项目").font(.caption).foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(20)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)

                        Button {
                            settingsSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("模板设置").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("编辑选题/文案/生图提示词模板和变量").font(.caption).foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(20)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }

                    // ── 最近项目列表 ──
                    if !vm.recentProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("最近项目").font(.headline)
                            ForEach(vm.recentProjects) { p in
                                NavigationLink(value: p) {
                                    ProjectCardView(project: p)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("AI图文工作流")
            .navigationDestination(for: Project.self) { p in
                TopicSelectionView(projectID: p.id, autoGenerate: true)
            }
            .sheet(isPresented: $settingsSheet) { SettingsView() }
            .onAppear { vm.setup(store: store) }
            .onChange(of: topicProjectID) { id in
                // NavigationLink 通过 NavigationStack 自动处理
            }
        }
    }
}
