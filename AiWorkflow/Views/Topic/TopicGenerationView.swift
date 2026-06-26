import SwiftUI

/// 选题生成页——不依赖已存在的 Project
///
/// 流程：
///   进入页面 → 自动调用 GPT 生成选题 → 用户选中一个
///   → 自动创建 Project → 导航到出文案页
struct TopicGenerationView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = TopicViewModel()
    @State private var navigateToCopy: UUID?  // projectID
    @State private var showAlert = false
    @State private var alertMsg = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ── 提示 ──
                HStack {
                    Image(systemName: "info.circle").font(.caption).foregroundColor(.secondary)
                    Text("当前使用默认选题模板").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // ── 操作区 ──
                HStack(spacing: 12) {
                    Button {
                        vm.generateTopics()
                    } label: {
                        HStack {
                            if vm.isLoading { ProgressView().tint(.white) }
                            Image(systemName: "sparkles")
                            Text(vm.isLoading ? "生成中..." : "生成选题")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isLoading)

                    Button {
                        vm.loadMockData()
                    } label: {
                        Text("测试数据")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                // ── 日志（调试） ──
                if !vm.lastLog.isEmpty {
                    Text(vm.lastLog).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── 内容 ──
                if vm.isLoading {
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.5)
                        Text("AI 正在为你生成选题...").foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if vm.topics.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "lightbulb").font(.system(size: 40)).foregroundColor(.secondary)
                        Text("点击「生成选题」开始").foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("已生成 \(vm.topics.count) 个选题", systemImage: "list.bullet")
                            .font(.subheadline.bold())

                        ForEach(vm.topics) { t in
                            Button {
                                guard let pid = vm.selectTopicAndCreateProject(t) else { return }
                                navigateToCopy = pid
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(t.title).font(.subheadline)
                                            .fontWeight(t.id == vm.selectedTopic?.id ? .semibold : .regular)
                                            .foregroundColor(.primary)
                                        if !t.topicDescription.isEmpty {
                                            Text(t.topicDescription).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if t.id == vm.selectedTopic?.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(t.id == vm.selectedTopic?.id ? Color.blue : Color(.systemGray5),
                                                lineWidth: t.id == vm.selectedTopic?.id ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("选题生成")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { navigateToCopy != nil },
            set: { if !$0 { navigateToCopy = nil } }
        )) {
            if let pid = navigateToCopy {
                CopyEditingView(projectID: pid)
            }
        }
        .onChange(of: vm.errorMessage) { msg in
            if let m = msg { alertMsg = m; showAlert = true }
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定") { vm.errorMessage = nil }
        } message: { Text(alertMsg) }
        .onAppear {
            print("🔵 TopicGenerationView.onAppear")
            vm.setup(textService: textService, store: store)
            // 自动生成选题
            if vm.topics.isEmpty && !vm.isLoading {
                vm.generateTopics()
            }
        }
    }
}
