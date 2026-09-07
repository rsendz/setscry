import CoreServices
import Foundation

/// FSEvents watches the whole hierarchy, including directories created later.
final class FolderWatcher {
    private final class Callback: Sendable {
        let changed: @Sendable () -> Void
        init(_ changed: @escaping @Sendable () -> Void) { self.changed = changed }
    }

    private let stream: FSEventStreamRef

    init(root: URL, changed: @escaping @Sendable () -> Void) throws {
        let callback = Callback(changed)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<Callback>.fromOpaque(pointer).retain()
                return pointer
            },
            release: { pointer in
                if let pointer { Unmanaged<Callback>.fromOpaque(pointer).release() }
            },
            copyDescription: nil
        )
        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue().changed()
            },
            &context, [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
        ) else { throw CocoaError(.fileReadUnknown) }

        // FSEvents requires a dispatch queue; all model work hops to MainActor.
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw CocoaError(.fileReadUnknown)
        }
        self.stream = stream
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
