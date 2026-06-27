import SwiftUI

/// 出图卡片——独立子视图
struct ImageCardView: View {
    let card: ImageCard
    let isGenerating: Bool
    let onGenerate: () -> Void
    let onRegenerate: () -> Void
    let onSaveToAlbum: () -> Void

    @State private var showDebug = false

    var body: some View {
        VStack(spacing: 6) {
            // 图片区
            ZStack {
                if let data = card.decodedImageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().aspectRatio(3/4, contentMode: .fit).cornerRadius(8)
                } else {
                    Rectangle().aspectRatio(3/4, contentMode: .fit).foregroundColor(placeholderBg).cornerRadius(8)
                        .overlay(statusOverlay)
                }
                if card.status == .success {
                    VStack { HStack { Spacer(); Text("图\(card.cardIndex+1)").font(.caption2).padding(.horizontal,6).padding(.vertical,3).background(Color.black.opacity(0.6)).foregroundColor(.white).cornerRadius(4).padding(4) }; Spacer() }
                }
            }

            // 状态行
            statusRow

            // 按钮
            HStack(spacing: 6) {
                if card.status == .success {
                    Button(action: onSaveToAlbum) { Image(systemName: "square.and.arrow.down").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                    Button(action: onRegenerate) { Image(systemName: "arrow.clockwise").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                } else if card.status == .idle || card.status == .failed || card.status == .timeout {
                    Button(action: onGenerate) { HStack { Image(systemName: "wand.and.stars"); Text("生成/重试").font(.caption) }.frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    ProgressView().scaleEffect(0.6); Text("处理中...").font(.caption2).foregroundColor(.secondary)
                }
            }

            // 调试区
            if card.status != .idle {
                Button { withAnimation { showDebug.toggle() } } label: { HStack { Image(systemName: showDebug ? "chevron.down" : "chevron.right"); Text("调试").font(.caption2) }.foregroundColor(.secondary) }
                if showDebug { debugPanel }
            }
        }
        .padding(6).background(cardBg).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isGenerating ? Color.orange.opacity(0.5) : (card.status == .success ? Color.green.opacity(0.2) : Color.clear), lineWidth: 0.5))
    }

    // MARK: - 子组件

    private var statusRow: some View {
        VStack(spacing: 2) {
            Text(statusLabel).font(.caption2).foregroundColor(statusColor)
            if let tid = card.taskId, card.status != .success {
                Text("ID: \(tid.prefix(12))...").font(.system(size: 8)).foregroundColor(.secondary)
            }
            if !card.efsIds.isEmpty, card.status != .success {
                Text("efs: \(card.efsIds.joined(separator: ",").prefix(20))...").font(.system(size: 8)).foregroundColor(.secondary)
            }
        }
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let e = card.errorMessage { Text(e).font(.system(size: 8)).foregroundColor(.red) }
            if let t = card.taskId { Text("task: \(t)").font(.system(size: 8)).foregroundColor(.secondary) }
            if !card.efsIds.isEmpty { Text("efs: \(card.efsIds.joined(separator: ","))").font(.system(size: 8)).foregroundColor(.secondary) }
            if !card.rawSubmitResponse.isEmpty { Text("提交: \(card.rawSubmitResponse.prefix(100))").font(.system(size: 7)).foregroundColor(.secondary) }
            if !card.rawQueryResponse.isEmpty { Text("查询: \(card.rawQueryResponse.prefix(100))").font(.system(size: 7)).foregroundColor(.secondary) }
            if let p = card.localFilePath { Text("路径: \(p)").font(.system(size: 7)).foregroundColor(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(4).background(Color(.systemGray6)).cornerRadius(4)
    }

    // MARK: - 状态衍生

    private var statusLabel: String {
        switch card.status {
        case .idle:"未生成"; case .generating:"生成中..."; case .success:"✅ 成功"; case .failed:"❌ 失败"
        case .parseFailed:"⚠️ 解析失败"; case .taskAccepted:"📋 已接收"; case .polling:"🔄 查询中"
        case .downloading:"⬇️ 下载中"; case .timeout:"⏰ 超时"; case .saveFailed:"⚠️ 保存失败"
        case .binaryImageReceived:"📷 已收到"; case .cancelled:"🚫 取消"
        }
    }
    private var statusColor: Color {
        switch card.status {
        case .idle:.secondary; case .generating:.orange; case .success:.green; case .failed:.red
        case .parseFailed:.orange; case .taskAccepted:.purple; case .polling:.orange
        case .downloading:.blue; case .timeout:.red; case .saveFailed:.orange; case .binaryImageReceived:.blue; case .cancelled:.gray
        }
    }
    private var placeholderBg: Color {
        (card.status == .failed || card.status == .timeout) ? Color.red.opacity(0.08) : Color(.systemGray5)
    }
    private var cardBg: Color {
        if card.status == .success { return Color.green.opacity(0.04) }
        if card.status == .failed || card.status == .timeout { return Color.red.opacity(0.03) }
        return Color(.systemGray6)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if card.status == .generating || card.status == .polling || card.status == .taskAccepted {
            VStack(spacing:6){ProgressView().scaleEffect(0.8);Text(statusLabel).font(.caption2)}.foregroundColor(.secondary)
        } else if card.status == .failed || card.status == .timeout {
            VStack(spacing:4){Image(systemName:"exclamationmark.triangle").font(.title2);Text(statusLabel).font(.caption2);if let e=card.errorMessage{Text(e).font(.caption2).foregroundColor(.secondary).lineLimit(2).multilineTextAlignment(.center)}}.foregroundColor(statusColor).padding(4)
        } else if card.status == .idle {
            VStack(spacing:4){Image(systemName:"photo").font(.title2);Text("未生成").font(.caption)}.foregroundColor(.secondary)
        }
    }
}
