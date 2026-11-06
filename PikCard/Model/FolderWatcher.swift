// 监听一个文件夹（含里面所有文件）的变化，用的是 macOS 自带的 FSEvents。
import Foundation

final class FolderWatcher {
    // 只在创建和销毁时碰它，不会有多线程同时访问
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    init(url: URL, onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        stream = FSEventStreamCreate(
            nil,
            { _, info, _, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                let list = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String]) ?? []
                // 回调在主线程队列上执行（见下面 SetDispatchQueue）
                MainActor.assumeIsolated { watcher.onChange(list) }
            },
            &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // 0.3 秒内的多次变化合并成一次
            flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
