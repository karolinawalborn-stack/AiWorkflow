import SwiftUI

struct HomeView: View {
    @Environment(\.projectStore) private var store
    @StateObject private var vm = HomeViewModel()
    @State private var settingsSheet = false
    @State private var goToTopics = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // ── 主入口区域 ──
                    VStack(spacing: 16) {
                        // 生成选题（主入口）
                        Button {
                            goToTopics = true
                        } label: {
                            HStack {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.blue)
                                    .cornerRadius(12)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("生成选题").font(.headline)
                                    Text("基于默认模板，AI 自动生成 6 个爆款选题").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(16)
                            .background(Color(.systemGray6))
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)

                        // 历史记录
                        NavigationLink {
                            HistoryListView()
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.purple)
                                    .cornerRadius(12)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("历史记录").font(.headline)
                                    Text("查看已完成和进行中的项目").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(vm.projects.count) 个").font(.caption).foregroundColor(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(16)
                            .background(Color(.systemGray6))
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)

                        // 模板设置
                        Button {
                            settingsSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.orange)
                                    .cornerRadius(12)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("模板设置").font(.headline)
                                    Text("编辑选题/文案/生图提示词模板").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(16)
                            .background(Color(.systemGray6))
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }

                    // ── 最近项目 ──
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
                CopyEditingView(projectID: p.id)
            }
            .navigationDestination(isPresented: $goToTopics) {
                TopicGenerationView()
            }
            .sheet(isPresented: $settingsSheet) {
                SettingsView()
            }
            .onAppear { vm.setup(store: store) }
        }
    }
}

extension Project: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
