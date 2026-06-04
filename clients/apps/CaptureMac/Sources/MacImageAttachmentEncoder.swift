import AppKit
import CaptureCore

enum MacImageAttachmentEncoder {
    private static let maxBytes = 512 * 1024
    private static let maxDimension: CGFloat = 1600

    static func draft(from image: NSImage, filename: String? = nil) -> TaskAttachmentDraft? {
        guard let scaled = scale(image) else { return nil }
        for quality in [0.82, 0.68, 0.54] {
            guard let data = scaled.jpegData(quality: quality) else { continue }
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

    private static func scale(_ image: NSImage) -> NSImage? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let longest = max(sourceSize.width, sourceSize.height)
        let ratio = longest > maxDimension ? maxDimension / longest : 1
        let targetSize = NSSize(width: sourceSize.width * ratio, height: sourceSize.height * ratio)
        let out = NSImage(size: targetSize)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}

private extension NSImage {
    func jpegData(quality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
