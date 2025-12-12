import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var folderURL: URL? = nil
    @State private var progress: Double = 0
    @State private var statusText: String = "请选择文件夹"
    @State private var totalFiles: Int = 0
    @State private var isDragOver = false
    @State private var isScanning = false

    @StateObject private var processor = FileProcessor()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("批量 MD5 修改器")
                .font(.system(size: 22, weight: .semibold))
            
            // 文件夹选择区域
            if processor.fileInfos.isEmpty {
                // 拖拽区域 - 未选择文件夹时显示
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragOver ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                        .stroke(
                            isDragOver ? Color.blue : Color.gray.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [8])
                        )
                        .frame(height: 200)

                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.title)
                            .foregroundColor(.secondary)
                        
                        Text("单击或拖拽选择文件夹")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
                .onTapGesture {
                    openFolderPanel()
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                    handleDrop(providers: providers)
                }
            }

            // 状态信息和按钮区域
            HStack(alignment: .top, spacing: 16) {
                // 状态信息 - 左对齐
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    
                    // 只在处理过程中或刚完成时显示统计
                    if processor.isRunning || (processor.processedCount > 0 && !processor.isRunning && progress > 0) {
                        HStack {
                            Text("成功: \(processor.successCount)")
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                            Text("失败: \(processor.failCount)")
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                            Text("总计: \(processor.processedCount)")
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 按钮组
                HStack(spacing: 8) {
                    if !processor.fileInfos.isEmpty {
                        Button(action: clearImages) {
                            Label("清空", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(minWidth: 50)
                    }
                    
                    Button(action: startOrStop) {
                        if processor.isRunning {
                            Label("停止处理", systemImage: "stop.fill")
                        } else {
                            Label("开始处理", systemImage: "play.fill")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(folderURL == nil || processor.isRunning || processor.fileInfos.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(minWidth: 120)
                }
            }
            .padding(.top, 8)

            // 进度条 - 只在处理过程中显示
            if processor.isRunning && totalFiles > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("处理进度")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(progress))/\(totalFiles)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: progress, total: Double(totalFiles))
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 8)
                }
            }
            
            // 照片网格显示
            if !processor.fileInfos.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200), spacing: 16)
                    ], spacing: 16) {
                        ForEach(processor.fileInfos) { fileInfo in
                            ImageCardView(fileInfo: fileInfo)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            
            Spacer()
        }
        .padding()
        .onChange(of: folderURL) { newValue in
            if let url = newValue {
                scanImagesInFolder(url)
            } else {
                processor.clearFileInfos()
                resetAllState()
                statusText = "请选择文件夹"
            }
        }
        .onReceive(processor.$processedCount) { newValue in
            progress = Double(newValue)
        }
        .onReceive(processor.$isRunning) { running in
            if running {
                if let folderName = folderURL?.lastPathComponent {
                    statusText = "正在处理文件夹：\(folderName)"
                } else {
                    statusText = "处理中…"
                }
            } else if processor.processedCount > 0 && progress > 0 {
                if processor.processedCount == totalFiles && totalFiles > 0 {
                    if let folderName = folderURL?.lastPathComponent {
                        statusText = "文件夹 \(folderName) 处理完成！"
                    } else {
                        statusText = "处理完成！"
                    }
                }
            }
        }
        .onReceive(processor.$currentFile) { file in
            if let file = file {
                statusText = "正在处理：\(file)"
            }
        }
    }
}

// MARK: - 照片卡片视图
struct ImageCardView: View {
    let fileInfo: FileInfo
    @State private var nsImage: NSImage? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 照片预览
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 200)
                
                if let image = nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("加载中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 文件名
            Text(fileInfo.url.lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            // MD5信息
            VStack(alignment: .leading, spacing: 4) {
                // 转换前MD5
                VStack(alignment: .leading, spacing: 2) {
                    Text("转换前:")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(fileInfo.originalMD5)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
                
                // 转换后MD5
                if let modifiedMD5 = fileInfo.modifiedMD5 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("转换后:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(modifiedMD5)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.blue)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                } else {
                    Text("未处理")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(4)
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        if let image = NSImage(contentsOf: fileInfo.url) {
            nsImage = image
        }
    }
}

// MARK: - 功能方法扩展
extension ContentView {
    // MARK: 打开文件夹
    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "请选择要处理的文件夹"
        panel.prompt = "选择"

        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
        }
    }

    // MARK: 处理拖拽
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                DispatchQueue.main.async {
                    if let data = data as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        self.processDroppedURL(url)
                    } else if let data = data as? Data,
                              let urlString = String(data: data, encoding: .utf8),
                              let url = URL(string: urlString) {
                        self.processDroppedURL(url)
                    }
                }
            }
            return true
        }
        
        return false
    }
    
    // MARK: 处理拖拽的URL
    private func processDroppedURL(_ url: URL) {
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                folderURL = url
            } else {
                folderURL = url.deletingLastPathComponent()
            }
        } else {
            statusText = "无法访问拖拽的路径"
        }
    }
    
    // MARK: 扫描文件夹中的照片
    func scanImagesInFolder(_ url: URL) {
        isScanning = true
        statusText = "正在扫描照片..."
        processor.scanImagesInFolder(url) { fileInfos in
            DispatchQueue.main.async {
                self.isScanning = false
                if fileInfos.isEmpty {
                    self.statusText = "文件夹中没有找到照片文件"
                } else {
                    self.statusText = "找到 \(fileInfos.count) 张照片，可以开始处理"
                }
            }
        }
    }

    // MARK: 开始/停止处理
    func startOrStop() {
        if processor.isRunning {
            processor.requestCancel()
            resetAllState()
            if let folderName = folderURL?.lastPathComponent {
                statusText = "已停止处理文件夹：\(folderName)"
            } else {
                statusText = "已停止处理"
            }
            return
        }

        guard let folder = folderURL else {
            statusText = "错误：请先选择文件夹"
            return
        }

        let byteCount = 1
        
        if let folderName = folderURL?.lastPathComponent {
            statusText = "正在准备处理文件夹：\(folderName)..."
        } else {
            statusText = "正在准备处理..."
        }
        
        processor.startProcessing(folder: folder, byteCount: byteCount) { fileCount in
            DispatchQueue.main.async {
                totalFiles = fileCount
                progress = 0
                if fileCount == 0 {
                    if let folderName = self.folderURL?.lastPathComponent {
                        self.statusText = "文件夹 \(folderName) 中没有找到文件"
                    } else {
                        self.statusText = "所选文件夹中没有找到文件"
                    }
                } else {
                    if let folderName = self.folderURL?.lastPathComponent {
                        self.statusText = "在文件夹 \(folderName) 中找到 \(fileCount) 个文件，开始处理..."
                    } else {
                        self.statusText = "找到 \(fileCount) 个文件，开始处理..."
                    }
                }
            }
        }
    }
    
    // MARK: 清空照片列表
    func clearImages() {
        processor.clearFileInfos()
        folderURL = nil
        resetAllState()
        statusText = "请选择文件夹"
    }
    
    // MARK: 重置UI状态
    private func resetUIState() {
        progress = 0
        totalFiles = 0
        isDragOver = false
    }
    
    // MARK: 重置所有状态（包括处理器状态）
    private func resetAllState() {
        resetUIState()
        processor.resetProcessingState()
    }
}
