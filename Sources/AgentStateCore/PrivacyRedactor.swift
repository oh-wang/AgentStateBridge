import CryptoKit
import Foundation

public enum PrivacyRedactor {
    public static func summarize(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        let shortHash = digest.prefix(5).map { String(format: "%02x", $0) }.joined()
        return "文字（\(string.count) 字，指纹 \(shortHash)）"
    }

    public static func summarizeValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return summarize(string)
        case let number as NSNumber:
            return "数字或布尔值（\(number)）"
        case let array as [Any]:
            return "列表（\(array.count) 项）"
        default:
            return "系统值（\(String(describing: type(of: value)))）"
        }
    }
}
