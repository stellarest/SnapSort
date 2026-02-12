import Foundation

final class DirectoryWatcher {
    private let url: URL
    private let queue = DispatchQueue(label: "SnapSort.DirectoryWatcher")
    private let eventHandler: () -> Void

    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, eventHandler: @escaping () -> Void) {
        self.url = url
        self.eventHandler = eventHandler
    }

    deinit {
        stop()
    }

    func start() throws {
        stop()

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            throw NSError(domain: "DirectoryWatcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to watch directory: \(url.path)"])
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.eventHandler()
        }

        source.setCancelHandler { [fileDescriptor] in
            if fileDescriptor >= 0 {
                close(fileDescriptor)
            }
        }

        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }
}
