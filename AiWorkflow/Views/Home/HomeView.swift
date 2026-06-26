import SwiftUI

struct HomeView: View {
    @Environment(\.projectStore) private var store
    @StateObject private var vm = HomeViewModel()
    @State private var settingsSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // ── 主入口区域 ──
                    VStack(spacing: 16) {
                        // 开始创作（主入口）
                        NavigationLink {
                            StartCreationView()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.pencil")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.blue)
                                    .cornerRadius(12)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("开始创作").font(.headline)
                                    Text("输入选题，一键生成整组双格漫画").font(.caption).foregroundColor(.secondary)
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
                                    Text("查看已完成的项目 (\(vm.projects.count))").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
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
                                    Text("编辑文案和生图提示词模板").font(.caption).foregroundColor(.secondary)
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
                CopyEditingView(projectID: p.id, userTopic: p.name, extraRequirements: "")
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
