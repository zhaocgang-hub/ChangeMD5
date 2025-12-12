import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - 文件信息结构
struct FileInfo: Identifiable {
    let id = UUID()
    let url: URL
    let originalMD5: String
    var modifiedMD5: String?
    var isProcessed: Bool = false
}

class FileProcessor: ObservableObject {
    
    @Published var isRunning = false
    @Published var processedCount = 0
    @Published var currentFile: String? = nil
    @Published var successCount = 0
    @Published var failCount = 0
    @Published var currentFileInfo: FileInfo? = nil
    @Published var fileInfos: [FileInfo] = [] // 存储所有文件的MD5信息

    private var workItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "file.process.queue")

    // MARK: - 扫描文件夹中的照片并计算原始MD5
    func scanImagesInFolder(_ folder: URL, completion: @escaping ([FileInfo]) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let imageURLs = self.collectImageFiles(in: folder)
            var fileInfos: [FileInfo] = []
            
            for imageURL in imageURLs {
                if let originalMD5 = MD5Helper.calculateMD5(for: imageURL) {
                    let fileInfo = FileInfo(url: imageURL, originalMD5: originalMD5)
                    fileInfos.append(fileInfo)
                }
            }
            
            DispatchQueue.main.async {
                self.fileInfos = fileInfos
                completion(fileInfos)
            }
        }
    }
    
    func startProcessing(folder: URL, byteCount: Int, completion: @escaping (Int) -> Void) {
        // 每次开始处理前重置状态（但保留fileInfos）
        resetProcessingState()
        
        // 只处理fileInfos中的照片文件
        let fileURLs = fileInfos.map { $0.url }
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

                // 获取已有的原始MD5
                guard let existingIndex = self.fileInfos.firstIndex(where: { $0.url == file }) else {
                    continue
                }
                let originalMD5 = self.fileInfos[existingIndex].originalMD5

                let success = self.simpleAppendRandomBytes(to: file, count: byteCount)
                
                // 计算修改后的MD5
                var modifiedMD5: String? = nil
                if success {
                    modifiedMD5 = MD5Helper.calculateMD5(for: file)
                }

                DispatchQueue.main.async {
                    self.processedCount += 1
                    if success {
                        self.successCount += 1
                        
                        // 更新fileInfos中的MD5信息
                        if let existingIndex = self.fileInfos.firstIndex(where: { $0.url == file }) {
                            self.fileInfos[existingIndex].modifiedMD5 = modifiedMD5
                            self.fileInfos[existingIndex].isProcessed = true
                        }
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
            self.currentFileInfo = nil
            // 注意：不清空fileInfos，保留照片列表和MD5信息
        }
    }
    
    // MARK: - 清空所有文件信息
    func clearFileInfos() {
        DispatchQueue.main.async {
            self.fileInfos = []
        }
    }

    // MARK: - 处理单个文件（带MD5计算）
    func processSingleFile(_ fileURL: URL, byteCount: Int, completion: @escaping (FileInfo?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 计算原始MD5
            guard let originalMD5 = MD5Helper.calculateMD5(for: fileURL) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            var fileInfo = FileInfo(url: fileURL, originalMD5: originalMD5)
            
            DispatchQueue.main.async {
                self.currentFileInfo = fileInfo
            }
            
            // 修改文件
            let success = self.simpleAppendRandomBytes(to: fileURL, count: byteCount)
            
            if success {
                // 计算修改后的MD5
                if let modifiedMD5 = MD5Helper.calculateMD5(for: fileURL) {
                    fileInfo.modifiedMD5 = modifiedMD5
                    fileInfo.isProcessed = true
                }
            }
            
            DispatchQueue.main.async {
                self.currentFileInfo = fileInfo
                completion(fileInfo)
            }
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
    
    // MARK: - 收集照片文件（递归）
    private func collectImageFiles(in folder: URL) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        let imageTypes: [UTType] = [.image]

        if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey])
                    if resourceValues.isRegularFile == true,
                       let contentType = resourceValues.contentType,
                       imageTypes.contains(where: { contentType.conforms(to: $0) }) {
                        results.append(fileURL)
                    }
                } catch {
                    // 如果无法获取文件信息，通过扩展名判断
                    let pathExtension = fileURL.pathExtension.lowercased()
                    let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp"]
                    if imageExtensions.contains(pathExtension) {
                        var isDirectory: ObjCBool = false
                        if fm.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                           !isDirectory.boolValue {
                            results.append(fileURL)
                        }
                    }
                }
            }
        }

        return results
    }
}
