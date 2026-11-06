// 压缩包和压缩数据：
//   Zip：.apkg 其实是 zip 压缩包，用系统自带的 ditto 解开 / 打包
//   Zstd：Anki 新版卡组里的数据库和图片用 zstd 压缩，用官方 C 代码解压（Vendor/zstd）
import Foundation

enum Zip {
    /// 解开压缩包。安全：先看一遍里面的文件名，有往外跳的路径（../、/开头）就不解
    static func extract(_ archive: URL, to folder: URL) throws {
        for name in try entries(of: archive) {
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            if name.hasPrefix("/") || name.hasPrefix("~") || parts.contains("..") {
                throw ArchiveError(message: L("压缩包里有不安全的文件路径，已停止导入：\(name)",
                                              "The archive contains an unsafe file path, import stopped: \(name)"))
            }
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try run(["-x", "-k", archive.path, folder.path])
    }

    /// 压缩包里所有文件的名字（用系统自带的 zipinfo）
    static func entries(of archive: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", archive.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ArchiveError(message: L("这不是一个有效的压缩包。", "This isn't a valid archive."))
        }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// 解出来的一个普通文件（不是“快捷方式”，也确实在解压文件夹里面）。不是就返回 nil
    static func safeFile(_ name: String, in folder: URL) -> URL? {
        let url = folder.appendingPathComponent(name)
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]),
              values.isSymbolicLink != true, values.isRegularFile == true else { return nil }
        let base = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base) else { return nil }
        return url
    }

    /// 把文件夹里的东西（不含文件夹本身）打成 zip
    static func create(from folder: URL, to archive: URL) throws {
        try? FileManager.default.removeItem(at: archive)
        try run(["-c", "-k", "--norsrc", "--noextattr", "--noqtn", folder.path, archive.path])
    }

    private static func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ArchiveError(message: message.isEmpty ? "ditto \(process.terminationStatus)" : message)
        }
    }
}

struct ArchiveError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Zstd {
    static func isCompressed(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual([0x28, 0xB5, 0x2F, 0xFD])
    }

    static func decompress(_ data: Data) throws -> Data {
        guard let stream = ZSTD_createDStream() else { throw ArchiveError(message: "zstd: out of memory") }
        defer { ZSTD_freeDStream(stream) }
        ZSTD_initDStream(stream)
        var output = Data()
        let chunkSize = ZSTD_DStreamOutSize()
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            var inBuffer = ZSTD_inBuffer(src: input.baseAddress, size: input.count, pos: 0)
            while inBuffer.pos < inBuffer.size {
                let produced: Int = try chunk.withUnsafeMutableBytes { out in
                    var outBuffer = ZSTD_outBuffer(dst: out.baseAddress, size: out.count, pos: 0)
                    let result = ZSTD_decompressStream(stream, &outBuffer, &inBuffer)
                    if ZSTD_isError(result) != 0 {
                        throw ArchiveError(message: "zstd: " + String(cString: ZSTD_getErrorName(result)))
                    }
                    return outBuffer.pos
                }
                output.append(contentsOf: chunk[0..<produced])
                if produced == 0 && inBuffer.pos >= inBuffer.size { break }
            }
            // 输入读完了，可能还有没吐出来的
            while true {
                var empty = ZSTD_inBuffer(src: nil, size: 0, pos: 0)
                let produced: Int = try chunk.withUnsafeMutableBytes { out in
                    var outBuffer = ZSTD_outBuffer(dst: out.baseAddress, size: out.count, pos: 0)
                    let result = ZSTD_decompressStream(stream, &outBuffer, &empty)
                    if ZSTD_isError(result) != 0 {
                        throw ArchiveError(message: "zstd: " + String(cString: ZSTD_getErrorName(result)))
                    }
                    return outBuffer.pos
                }
                if produced == 0 { break }
                output.append(contentsOf: chunk[0..<produced])
            }
        }
        return output
    }
}

/// 读 protobuf（Anki 新版用它存媒体清单和笔记类型），只需要很少的功能
struct ProtoReader {
    private let data: [UInt8]
    private var i = 0

    init(_ data: Data) { self.data = [UInt8](data) }

    enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    /// 读下一个字段：(编号, 值)。读完了返回 nil
    mutating func next() -> (Int, Value)? {
        while i < data.count {
            guard let key = varint() else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0: guard let v = varint() else { return nil }; return (field, .varint(v))
            case 2:
                guard let length = varint(), i + Int(length) <= data.count else { return nil }
                let bytes = Data(data[i..<i + Int(length)])
                i += Int(length)
                return (field, .bytes(bytes))
            case 1: i += 8
            case 5: i += 4
            default: return nil
            }
        }
        return nil
    }

    private mutating func varint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while i < data.count {
            let byte = data[i]
            i += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}
