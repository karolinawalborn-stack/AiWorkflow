import SwiftUI

/// 批量导入提示词——独立子视图
struct PromptBatchImportView: View {
    @Binding var text: String
    let onImport: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("批量导入提示词").font(.headline)
                Text("每行一条，或空行分隔。支持「第N条」格式。").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $text)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 200).padding(8)
                    .background(Color(.systemGray6)).cornerRadius(8)
                HStack(spacing: 12) {
                    Button("取消") { onCancel() }.buttonStyle(.bordered)
                    Button("导入并填充") { onImport(text) }.buttonStyle(.borderedProminent)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
