import Foundation
import Combine

@MainActor
final class FileWatcher: ObservableObject {
    @Published var lastChange: Date = Date()

    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []

    func watch(directories: [URL]) {
        stopAll()

        for dir in directories {
            guard FileManager.default.fileExists(atPath: dir.path()) else { continue }

            let fd = open(dir.path(), O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend],
                queue: .main
            )

            source.setEventHandler { [weak self] in
                self?.lastChange = Date()
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            sources.append(source)
        }
    }

    func stopAll() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
    }

    deinit {
        MainActor.assumeIsolated {
            stopAll()
        }
    }
}
