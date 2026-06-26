import SwiftUI

struct ProjectCardView: View {
    let project: Project
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.name).font(.headline).lineLimit(1)
                Spacer()
                Text(project.status.displayName).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(6)
            }
            HStack(spacing: 12) {
                Label(project.category, systemImage: "tag"); Label("\(project.imageCount)张", systemImage: "photo.on.rectangle")
                if !project.ratio.isEmpty { Label(project.ratio, systemImage: "rectangle.ratio.3.to.4") }
            }.font(.caption).foregroundColor(.secondary)
            ProgressView(value: project.status.progressValue).tint(color)
            Text("更新 \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundColor(.secondary)
        }.padding().background(Color(.systemBackground)).cornerRadius(12).shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
    private var color: Color {
        switch project.status {
        case .draft: return .gray
        case .topicsReady, .topicSelected: return .blue
        case .copyReady: return .purple
        case .promptsReady: return .orange
        case .imagesReady: return .green
        case .completed: return .green
        }
    }
}

struct ProgressHeader: View {
    let title: String; let step: Int; let total: Int; let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).font(.headline); Spacer(); Text("步骤 \(step)/\(total)").font(.caption).foregroundColor(.secondary) }
            ProgressView(value: Double(step)/Double(total)).tint(tint)
        }.padding().background(Color(.systemGray6)).cornerRadius(12)
    }
}
