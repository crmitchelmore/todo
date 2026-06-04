import UIKit

extension UIImage {
    convenience init?(dataURL: String) {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let payload = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: payload) else { return nil }
        self.init(data: data)
    }
}
