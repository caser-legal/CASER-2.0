import PDFKit
import Photos
import UIKit

struct PDFPhotoExportPolicy: Sendable {
    static let outputScale: CGFloat = 2
    static let maximumPageCount = 50
    static let maximumPixelDimension = 4_096
    static let maximumTotalPixelCount: Int64 = 100_000_000

    enum Violation: Equatable, Sendable {
        case invalidPageCount
        case tooManyPages
        case invalidPageBounds
        case pageDimensionExceeded
        case totalPixelBudgetExceeded
    }

    static func outputPixelSize(for bounds: CGRect) -> CGSize {
        CGSize(
            width: ceil(bounds.width * outputScale),
            height: ceil(bounds.height * outputScale)
        )
    }

    static func validate(pageBounds: [CGRect]) -> Violation? {
        guard !pageBounds.isEmpty else { return .invalidPageCount }
        guard pageBounds.count <= maximumPageCount else { return .tooManyPages }

        var totalPixels: Int64 = 0
        for bounds in pageBounds {
            guard bounds.width.isFinite,
                  bounds.height.isFinite,
                  bounds.width > 0,
                  bounds.height > 0 else {
                return .invalidPageBounds
            }

            let pixelSize = outputPixelSize(for: bounds)
            guard pixelSize.width <= CGFloat(maximumPixelDimension),
                  pixelSize.height <= CGFloat(maximumPixelDimension) else {
                return .pageDimensionExceeded
            }

            let pagePixels = pixelSize.width * pixelSize.height
            guard pagePixels.isFinite, pagePixels <= CGFloat(Int64.max) else {
                return .totalPixelBudgetExceeded
            }
            totalPixels += Int64(pagePixels)
            guard totalPixels <= maximumTotalPixelCount else {
                return .totalPixelBudgetExceeded
            }
        }
        return nil
    }
}

enum PDFPhotosSaver {
    enum SaveError: LocalizedError {
        case invalidPDF
        case permissionDenied
        case tooManyPages(Int)
        case pageTooLarge
        case totalPixelBudgetExceeded
        case renderFailed(page: Int)
        case cancelled
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidPDF:
                return "This PDF could not be read."
            case .permissionDenied:
                return "Photo library access was denied. Enable access in Settings to save pages."
            case .tooManyPages(let limit):
                return "This PDF has too many pages to save safely. Export up to \(limit) pages at a time."
            case .pageTooLarge:
                return "A page in this PDF is too large to save safely."
            case .totalPixelBudgetExceeded:
                return "This PDF is too large to convert to photos safely. Export fewer pages and try again."
            case .renderFailed(let page):
                return "Page \(page) could not be rendered. No pages were saved."
            case .cancelled:
                return "Saving to Photos was cancelled."
            case .saveFailed(let message):
                return message
            }
        }
    }

    private struct RenderedBatch: Sendable {
        let directory: URL
        let imageFiles: [URL]
    }

    static func saveToPhotos(url: URL) async -> Result<Int, SaveError> {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return .failure(.permissionDenied)
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }

        let renderTask = Task.detached(priority: .userInitiated) {
            try renderPageFiles(from: url)
        }
        let renderResult = await withTaskCancellationHandler {
            await renderTask.result
        } onCancel: {
            renderTask.cancel()
        }

        let batch: RenderedBatch
        switch renderResult {
        case .success(let value):
            batch = value
        case .failure(let error as SaveError):
            return .failure(error)
        case .failure(let error):
            if error is CancellationError {
                return .failure(.cancelled)
            }
            return .failure(.saveFailed(error.localizedDescription))
        }

        defer { try? FileManager.default.removeItem(at: batch.directory) }
        guard !Task.isCancelled else { return .failure(.cancelled) }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for fileURL in batch.imageFiles {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                }
            }
            return .success(batch.imageFiles.count)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    nonisolated private static func renderPageFiles(from url: URL) throws -> RenderedBatch {
        try Task.checkCancellation()
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw SaveError.invalidPDF
        }

        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        guard pages.count == document.pageCount else {
            throw SaveError.invalidPDF
        }
        let pageBounds = pages.map { $0.bounds(for: .mediaBox) }
        if let violation = PDFPhotoExportPolicy.validate(pageBounds: pageBounds) {
            switch violation {
            case .invalidPageCount, .invalidPageBounds:
                throw SaveError.invalidPDF
            case .tooManyPages:
                throw SaveError.tooManyPages(PDFPhotoExportPolicy.maximumPageCount)
            case .pageDimensionExceeded:
                throw SaveError.pageTooLarge
            case .totalPixelBudgetExceeded:
                throw SaveError.totalPixelBudgetExceeded
            }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CASER-Photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )

        var completed = false
        defer {
            if !completed {
                try? FileManager.default.removeItem(at: directory)
            }
        }

        var imageFiles: [URL] = []
        imageFiles.reserveCapacity(pages.count)

        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let imageFile: URL = try autoreleasepool {
                guard let image = renderPage(page) else {
                    throw SaveError.renderFailed(page: index + 1)
                }
                try Task.checkCancellation()
                guard let jpeg = image.jpegData(compressionQuality: 0.92) else {
                    throw SaveError.renderFailed(page: index + 1)
                }
                let destination = directory.appendingPathComponent(
                    String(format: "page-%03d.jpg", index + 1),
                    isDirectory: false
                )
                try jpeg.write(to: destination, options: [.atomic, .completeFileProtection])
                return destination
            }
            imageFiles.append(imageFile)
        }

        completed = true
        return RenderedBatch(directory: directory, imageFiles: imageFiles)
    }

    nonisolated private static func renderPage(_ page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = PDFPhotoExportPolicy.outputScale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }
}
