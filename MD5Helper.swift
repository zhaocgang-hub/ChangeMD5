import Foundation
import CryptoKit

struct MD5Helper {
    /// 计算文件的MD5值
    static func calculateMD5(for fileURL: URL) -> String? {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        let hash = Insecure.MD5.hash(data: fileData)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// 计算数据的MD5值
    static func calculateMD5(for data: Data) -> String {
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

