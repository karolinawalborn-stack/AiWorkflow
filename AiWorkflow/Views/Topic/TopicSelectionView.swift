import SwiftUI

struct TopicSelectionView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = TopicViewModel()
    @State private var goNext = false
    @State private var showAlert = false
    @State private var alertMsg = ""
    let projectID: UUID
    let autoGenerate: Bool

    init(projectID: UUID, autoGenerate: Bool = false) {
        self.projectID = projectID
        self.autoGenerate = autoGenerate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ── 进度头 ──
                ProgressHeader(title: vm.project?.name ?? "选题", step: 1, total: 4, tint: .blue)

                // ── 日志 ──
                if !vm.lastDebugLog.isEmpty {
                    Text(vm.lastDebugLog).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── 操作区 ──
                HStack(spacing: 12) {
                    Button {
                        print("🔵 [UI] 生成选题按钮点击")
                        vm.generateTopics()
                    } label: {
                        HStack {
                            if vm.isLoading { ProgressView().tint(.white) }
                            Image(systemName: "sparkles")
                            Text(vm.isLoading ? "生成中..." : "重新生成选题")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isLoading)

                    Button {
                        print("🟠 [UI] 加载测试数据")
                        vm.loadMockData()
                    } label: {
                        HStack { Image(systemName: "ladybug"); Text("测试数据") }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                // ── 内容 ──
                if vm.isLoading {
                    VStack(spacing: 12) { ProgressView().scaleEffect(1.5); Text("AI 正在生成选题...").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if vm.topics.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "lightbulb").font(.system(size: 40)).foregroundColor(.secondary); Text("点击「生成选题」开始").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("选题列表（\(vm.topics.count)个）", systemImage: "list.bullet").font(.subheadline.bold())

                        ForEach(vm.topics) { t in
                            Button { vm.selectTopic(t) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(t.title).font(.subheadline).fontWeight(t.id == vm.selectedTopicID ? .semibold : .regular).foregroundColor(.primary).lineLimit(2)
                                        if !t.topicDescription.isEmpty { Text(t.topicDescription).font(.caption).foregroundColor(.secondary).lineLimit(2) }
                                    }
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Button { vm.toggleFavorite(t) } label: { Image(systemName: t.isFavorited ? "heart.fill" : "heart").foregroundColor(t.isFavorited ? .red : .gray).font(.caption) }.buttonStyle(.plain)
                                        if t.id == vm.selectedTopicID { Image(systemName: "checkmark.circle.fill").foregroundColor(.blue) }
                                    }
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 10).stroke(t.id == vm.selectedTopicID ? Color.blue : Color(.systemGray5), lineWidth: t.id == vm.selectedTopicID ? 2 : 1))
                            }.buttonStyle(.plain)
                        }

                        if vm.selectedTopicID != nil {
                            Button { goNext = true } label: { Text("选择此选题，进入文案编辑 →").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }.padding()
        }
        .navigationTitle("选题").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goNext) { CopyEditingView(projectID: projectID) }
        .onAppear {
            print("🔵 [UI] TopicSelectionView.onAppear, projectID=\(projectID)")
            if let p = store?.project(id: projectID) {
                print("✅ [UI] 已加载 project: \(p.name)")
                vm.setup(store: store!, textService: textService, project: p)
                if autoGenerate && p.topicCandidates.isEmpty {
                    print("🔄 [UI] autoGenerate=true，自动触发生成选题")
                    vm.generateTopics()
                }
            } else {
                print("❌ [UI] project 未找到")
                alertMsg = "项目不存在"; showAlert = true
            }
        }
        .onChange(of: vm.errorMessage) { msg in if let m = msg { alertMsg = m; showAlert = true } }
        .alert("提示", isPresented: $showAlert) { Button("确定") { vm.errorMessage = nil } } message: { Text(alertMsg) }
    }
}
