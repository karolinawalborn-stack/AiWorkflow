import SwiftUI

/// 开始创作页——输入选题即可开始
struct StartCreationView: View {
    @Environment(\.projectStore) private var store
    @StateObject private var vm = StartCreationViewModel()
    @State private var navigateToCopy: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ── 头部说明 ──
                VStack(spacing: 8) {
                    Image(systemName: "square.and.pencil").font(.system(size: 36)).foregroundColor(.blue)
                    Text("输入选题，开始创作").font(.title3).fontWeight(.semibold)
                    Text("输入一个双格漫画选题，AI 将自动生成全套文案、提示词和图片")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // ── 选题输入 ──
                VStack(alignment: .leading, spacing: 6) {
                    Text("选题 *").font(.headline)
                    TextEditor(text: $vm.topicInput)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    if vm.topicInput.isEmpty {
                        Text("例如：你不是脾气不好，是委屈攒够了")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                // ── 补充要求（可选） ──
                VStack(alignment: .leading, spacing: 6) {
                    Text("补充要求（可选）").font(.headline)
                    TextEditor(text: $vm.extraRequirements)
                        .frame(minHeight: 60)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    Text("例如：风格参考深蓝黑压抑情绪漫画，白色圆头小人")
                        .font(.caption).foregroundColor(.secondary)
                }

                // ── 生成按钮 ──
                Button {
                    guard let pid = vm.createProject(store: store) else { return }
                    navigateToCopy = pid
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("生成文案")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.isValid)
            }
            .padding()
        }
        .navigationTitle("开始创作")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { navigateToCopy != nil },
            set: { if !$0 { navigateToCopy = nil } }
        )) {
            if let pid = navigateToCopy {
                CopyEditingView(projectID: pid, userTopic: vm.topicInput, extraRequirements: vm.extraRequirements)
            }
        }
    }
}
