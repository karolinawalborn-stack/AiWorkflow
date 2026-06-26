import SwiftUI

struct TopicSelectionView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = TopicViewModel()
    @State private var goNext = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    let projectID: UUID

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ── 进度头 ──
                ProgressHeader(title: vm.project?.name ?? "选题", step: 1, total: 4, tint: .blue)

                // ── 定位输入区 ──
                VStack(alignment: .leading, spacing: 8) {
                    Label("账号定位", systemImage: "target").font(.subheadline.bold())
                    TextEditor(text: $vm.positioningInput)
                        .frame(minHeight: 80).padding(8)
                        .background(Color(.systemGray6)).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 1))
                }

                // ── 操作按钮 ──
                VStack(spacing: 12) {
                    Button {
                        print("🔵 [UI] 生成选题按钮被点击")
                        vm.generateTopics()
                    } label: {
                        HStack {
                            if vm.isLoading {
                                ProgressView().tint(.white)
                            }
                            Image(systemName: "sparkles")
                            Text(vm.isLoading ? "生成中..." : "生成选题")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isLoading)

                    Button {
                        print("🟠 [UI] 加载测试选题按钮被点击")
                        vm.loadMockData()
                    } label: {
                        HStack {
                            Image(systemName: "ladybug")
                            Text("加载测试选题（跳过 API）")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                // ── 日志（调试用） ──
                if !vm.lastDebugLog.isEmpty {
                    Text(vm.lastDebugLog)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── 内容区域 ──
                if vm.isLoading {
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.5)
                        Text("AI 正在生成选题...").foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if vm.topics.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "lightbulb").font(.system(size: 40)).foregroundColor(.secondary)
                        Text("点击「生成选题」或「加载测试选题」").foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("选题列表（\(vm.topics.count)个）", systemImage: "list.bullet").font(.subheadline.bold())

                        ForEach(vm.topics) { t in
                            Button { vm.selectTopic(t) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(t.title).font(.subheadline)
                                            .fontWeight(t.id == vm.selectedTopicID ? .semibold : .regular)
                                            .foregroundColor(.primary).lineLimit(2)
                                        if !t.topicDescription.isEmpty {
                                            Text(t.topicDescription).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Button { vm.toggleFavorite(t) } label: {
                                            Image(systemName: t.isFavorited ? "heart.fill" : "heart")
                                                .foregroundColor(t.isFavorited ? .red : .gray).font(.caption)
                                        }.buttonStyle(.plain)
                                        if t.id == vm.selectedTopicID {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                                        }
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(t.id == vm.selectedTopicID ? Color.blue : Color(.systemGray5),
                                                lineWidth: t.id == vm.selectedTopicID ? 2 : 1)
                                )
                            }.buttonStyle(.plain)
                        }

                        if vm.selectedTopicID != nil {
                            Button { goNext = true } label: {
                                Text("选择此选题，进入文案编辑 →").frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("选题").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goNext) {
            if let p = vm.project { CopyEditingView(projectID: projectID) }
        }
        .onAppear {
            print("🔵 [UI] TopicSelectionView.onAppear, projectID=\(projectID)")
            if let p = store.project(id: projectID) {
                print("✅ [UI] 找到 project: \(p.name)")
                vm.setup(store: store, textService: textService, project: p)
            } else {
                print("❌ [UI] store.project(id:) 返回 nil！projectID=\(projectID)")
                alertMessage = "项目数据未找到，请返回首页重试"
                showAlert = true
            }
        }
        .onChange(of: vm.errorMessage) { msg in
            if let msg = msg { alertMessage = msg; showAlert = true }
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定") { vm.errorMessage = nil }
        } message: { Text(alertMessage) }
    }
}
