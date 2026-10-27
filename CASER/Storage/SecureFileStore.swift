import Foundation
import os.log

private let secureStoreLogger = Logger(subsystem: "com.caser.app", category: "SecureFileStore")

struct SecureFileStore: Sendable {
    private let directoryName = "SecureStore"
    private let protection: FileProtectionType
    private let ioQueue: DispatchQueue

    init(protection: FileProtectionType = .complete) {
        self.protection = protection
        self.ioQueue = DispatchQueue(
            label: "com.caser.app.SecureFileStore.io",
            qos: .utility
        )
    }

    private func directoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.protectionKey: protection],
                ofItemAtPath: dir.path
            )
        }
        return dir
    }

    private func fileURL(for filename: String) throws -> URL {
        let dir = try directoryURL()
        return dir.appendingPathComponent(filename, isDirectory: false)
    }

    func save(_ data: Data, to filename: String) throws {
        let protection = self.protection
        try ioQueue.sync {
            var url = try fileURL(for: filename)
            let options: Data.WritingOptions = protection == .completeUntilFirstUserAuthentication
                ? [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                : [.atomic, .completeFileProtection]
            try data.write(to: url, options: options)
            try FileManager.default.setAttributes(
                [.protectionKey: protection],
                ofItemAtPath: url.path
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try url.setResourceValues(resourceValues)
        }
    }

    func applyProtection(to filename: String) {
        let protection = self.protection
        ioQueue.sync {
            guard let url = try? fileURL(for: filename),
                  FileManager.default.fileExists(atPath: url.path) else { return }
            try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
        }
    }

    func load(from filename: String) throws -> Data {
        try ioQueue.sync {
            let url = try fileURL(for: filename)
            return try Data(contentsOf: url)
        }
    }

    func delete(_ filename: String) throws {
        try ioQueue.sync {
            let url = try fileURL(for: filename)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    func exists(_ filename: String) -> Bool {
        ioQueue.sync {
            (try? fileURL(for: filename)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        }
    }
}
