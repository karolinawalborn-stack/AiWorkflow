import SwiftUI

extension Color {
    static let cardBg = Color(.systemGray6)
}

extension String {
    var isNotBlank: Bool { !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func truncate(to length: Int, trail: String = "...") -> String { count > length ? prefix(length) + trail : self }
}
