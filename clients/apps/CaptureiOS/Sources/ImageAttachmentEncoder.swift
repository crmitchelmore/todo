import UIKit
import CaptureCore

enum ImageAttachmentEncoder {
    private static let maxBytes = 512 * 1024
    private static let maxDimension: CGFloat = 1600

    static func draft(from image: UIImage, filename: String? = nil) -> TaskAttachmentDraft? {
        let scaled = scale(image)
        for quality in [0.82, 0.68, 0.54] {
            guard let data = scaled.jpegData(compressionQuality: quality) else { continue }
            guard data.count <= maxBytes else { continue }
            return TaskAttachmentDraft(
                filename: filename ?? "Image attachment.jpg",
                mimeType: "image/jpeg",
                byteSize: data.count,
                previewDataURL: "data:image/jpeg;base64,\(data.base64EncodedString())"
            )
        }
        return nil
    }

    private static func scale(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let ratio = maxDimension / longest
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
