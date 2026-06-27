import SwiftUI

/// 单张提示词编辑器——独立子视图，避免编译器超时
struct PromptEditorView: View {
    let text: String
    let index: Int
    let isGenerating: Bool
    let onEdit: (String) -> Void
    let onCopy: () -> Void

    @State private var editText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("图\(index+1)").font(.caption).fontWeight(.semibold).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(text.isEmpty ? Color.secondary : Color.green).cornerRadius(6)
                Spacer()
                if !text.isEmpty {
                    Button(action: onCopy) { Image(systemName: "doc.on.doc").font(.caption) }.buttonStyle(.plain)
                }
            }
            if isGenerating {
                HStack { ProgressView().scaleEffect(0.8); Text("生成中...").font(.caption).foregroundColor(.secondary) }.padding(.vertical, 8)
            } else {
                TextEditor(text: $editText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 60).padding(6)
                    .background(Color(.systemGray6)).cornerRadius(6)
                    .onChange(of: editText) { onEdit($0) }
            }
        }
        .padding(12).background(text.isEmpty ? Color(.systemGray6) : Color.green.opacity(0.04)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isGenerating ? Color.orange.opacity(0.5) : Color.clear, lineWidth: isGenerating ? 1.5 : 0.5))
        .onAppear { editText = text }
        .onChange(of: text) { if $0 != editText { editText = $0 } }
    }
}
