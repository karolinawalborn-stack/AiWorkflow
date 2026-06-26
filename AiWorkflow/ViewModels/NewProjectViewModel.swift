import SwiftUI

@MainActor
final class NewProjectViewModel: ObservableObject {
    @Published var projectName: String = ""
    @Published var category: String = "双格漫画"
    @Published var style: String = "深蓝黑压抑情绪漫画，白色圆头小人"
    @Published var imageCount: Int = 6
    @Published var ratio: String = "3:4"
    @Published var ipStyle: String = "白色圆头小人，深蓝黑背景，压抑情绪风格，上下双格布局，带字幕框"

    let categoryOptions = ["双格漫画", "心理成因", "情感关系", "个人成长", "职场"]
    let ratioOptions = ["3:4", "1:1", "9:16"]
    let imageCountOptions = [4, 6, 8, 10]

    var isFormValid: Bool { !projectName.trimmingCharacters(in: .whitespaces).isEmpty }

    func load(from project: Project) {
        projectName = project.name; category = project.category; style = project.style
        imageCount = project.imageCount; ratio = project.ratio; ipStyle = project.ipStyle
    }

    func buildProject(existing: Project?) -> Project {
        let p: Project
        if let ex = existing { p = ex } else { p = Project(name: projectName) }
        var r = p
        r.name = projectName; r.category = category; r.style = style
        r.imageCount = imageCount; r.ratio = ratio; r.ipStyle = ipStyle
        r.updatedAt = Date()
        return r
    }
}
