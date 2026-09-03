import Darwin
import Foundation

final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1

    init?(directory: URL, queue: DispatchQueue = .main, handler: @escaping () -> Void) {
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler { [descriptor] in close(descriptor) }
        self.source = source
        source.resume()
    }

    func cancel() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit { cancel() }
}
