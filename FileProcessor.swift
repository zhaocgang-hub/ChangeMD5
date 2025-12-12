import Foundation
import SwiftUI
import Combine

class FileProcessor: ObservableObject {
    
    @Published var isRunning = false
    @Published var processedCount = 0
    @Published var currentFile: String? = nil
    @Published var successCount = 0
    @Published var failCount = 0

    private var workItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "file.process.queue")

    func startProcessing(folder: URL, byteCount: Int, completion: @escaping (Int) -> Void) {
        // 每次开始处理前重置状态
        resetProcessingState()
        
        let fileURLs = collectFiles(in: folder)
        let totalFiles = fileURLs.count
        
        completion(totalFiles)
        
        DispatchQueue.main.async {
            self.isRunning = true
        }
        
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            for file in fileURLs {
                if self.workItem?.isCancelled == true { break }

                DispatchQueue.main.async {
                    self.currentFile = file.lastPathComponent
                }

                let success = self.simpleAppendRandomBytes(to: file, count: byteCount)

                DispatchQueue.main.async {
                    self.processedCount += 1
                    if success {
                        self.successCount += 1
                    } else {
                        self.failCount += 1
                    }
                }
            }

            DispatchQueue.main.async {
                self.isRunning = false
                self.currentFile = nil
            }
        }
        
        if let item = workItem {
            queue.async(execute: item)
        }
    }

    func requestCancel() {
        workItem?.cancel()
        DispatchQueue.main.async {
            self.isRunning = false
            self.currentFile = nil
        }
    }
    
    // MARK: 重置处理状态（公开方法）
    func resetProcessingState() {
        DispatchQueue.main.async {
            self.processedCount = 0
            self.successCount = 0
            self.failCount = 0
            self.currentFile = nil
        }
    }

    // MARK: - 简单的文件追加方法
    private func simpleAppendRandomBytes(to file: URL, count: Int) -> Bool {
        guard count > 0 else { return false }
        
        do {
            let fileData = try Data(contentsOf: file)
            var randomData = Data()
            for _ in 0..<count {
                randomData.append(UInt8.random(in: 0...255))
            }
            
            let newData = fileData + randomData
            try newData.write(to: file)
            return true
            
        } catch {
            print("文件操作失败: \(file.lastPathComponent) - \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 收集文件（递归）
    private func collectFiles(in folder: URL) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default

        if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    if resourceValues.isRegularFile == true {
                        results.append(fileURL)
                    }
                } catch {
                    // 如果无法获取文件信息，假设是普通文件
                    var isDirectory: ObjCBool = false
                    if fm.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                       !isDirectory.boolValue {
                        results.append(fileURL)
                    }
                }
            }
        }

        return results
    }
}
