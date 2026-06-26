import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class MockImageService: AIImageServiceProtocol {
    func generateImage(prompt: String, size: String, n: Int) async throws -> [GeneratedImageResult] {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        return (0..<n).map { _ in
            GeneratedImageResult(data: Self.placeholder(size: size), url: nil, revisedPrompt: "【Mock】\(prompt)")
        }
    }

    private static func placeholder(size: String) -> Data? {
        #if canImport(UIKit)
        let parts = size.split(separator: "x").compactMap { Int($0) }
        let dim = CGSize(width: parts.first ?? 1024, height: parts.last ?? 1792)
        let renderer = UIGraphicsImageRenderer(size: dim)
        let image = renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(origin: .zero, size: dim))
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20),
                .foregroundColor: UIColor.lightGray,
                .paragraphStyle: style,
            ]
            ("双格漫画\nMock Image" as NSString).draw(in: CGRect(x: 0, y: dim.height/2 - 30, width: dim.width, height: 60), withAttributes: attrs)
        }
        return image.jpegData(compressionQuality: 0.8)
        #else
        return nil
        #endif
    }
}
