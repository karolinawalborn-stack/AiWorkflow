import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) { Text("API Base URL").font(.caption).foregroundColor(.secondary); TextField("https://api.lk888.ai/api", text: $vm.apiBaseURL).textContentType(.URL).autocapitalization(.none).disableAutocorrection(true).keyboardType(.URL) }
                    VStack(alignment: .leading, spacing: 4) { Text("API Key").font(.caption).foregroundColor(.secondary)
                        HStack { if vm.isAPIKeyVisible { TextField("sk-...", text: $vm.apiKey).autocapitalization(.none).disableAutocorrection(true) } else { SecureField("sk-...", text: $vm.apiKey) }
                            Button { vm.isAPIKeyVisible.toggle() } label: { Image(systemName: vm.isAPIKeyVisible ? "eye.slash" : "eye").foregroundColor(.secondary) }.buttonStyle(.plain) }
                    }
                    Button { Task { await vm.validateConnection() } } label: { HStack { Image(systemName: "antenna.radiowaves.left.and.right"); Text(vm.isValidating ? "验证中..." : "验证连接") } }.disabled(vm.isValidating)
                } header: { Text("API配置").foregroundColor(.secondary) }

                Section {
                    VStack(alignment: .leading, spacing: 4) { Text("文本模型 (GPT-5.4)").font(.caption).foregroundColor(.secondary); TextField("gpt-5.4", text: $vm.textModelID).autocapitalization(.none).disableAutocorrection(true) }
                    VStack(alignment: .leading, spacing: 4) { Text("图片模型 (GPT Image 2)").font(.caption).foregroundColor(.secondary); TextField("gpt-image-2", text: $vm.imageModelID).autocapitalization(.none).disableAutocorrection(true) }
                } header: { Text("模型配置").foregroundColor(.secondary) }

                Section {
                    TextEditor(text: $vm.defaultPromptTemplate).frame(minHeight: 120).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))
                } header: { Text("默认提示词模板").foregroundColor(.secondary) }

                Section {
                    HStack { Text("版本"); Spacer(); Text("1.0.0").foregroundColor(.secondary) }
                    HStack { Text("目标平台"); Spacer(); Text("iOS 16+ / TrollStore").foregroundColor(.secondary) }
                    HStack { Text("赛道"); Spacer(); Text("双格漫画").foregroundColor(.secondary) }
                } header: { Text("关于").foregroundColor(.secondary) }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("重置") { vm.resetToDefaults() } } }
        }
    }
}
