import SwiftUI

/// 单条提示词编辑 Sheet——独立子视图，避免编译器动态成员问题
struct PromptEditSheetView: View {
    let vm: PromptViewModel
    let cardIndex: Int
    let onDone: () -> Void

    @State private var editText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("编辑图\(cardIndex+1) 提示词").font(.headline)
                TextEditor(text: $editText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 200).padding(8)
                    .background(Color(.systemGray6)).cornerRadius(8)
                HStack(spacing: 12) {
                    Button("取消") { onDone() }.buttonStyle(.bordered)
                    Button("保存") { vm.updatePrompt(at: cardIndex, prompt: editText, description: ""); onDone() }.buttonStyle(.borderedProminent)
                }
            }.padding()
        }
    }
}
