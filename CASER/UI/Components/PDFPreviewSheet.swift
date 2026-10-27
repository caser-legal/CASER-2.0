import PDFKit
import SwiftUI
import UIKit

struct PDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let deleteOnDismiss: Bool

    init(url: URL, title: String, deleteOnDismiss: Bool = true) {
        self.url = url
        self.title = title
        self.deleteOnDismiss = deleteOnDismiss
    }

    func removeTemporaryFileIfNeeded() {
        guard deleteOnDismiss, url.isFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

struct PDFPreviewSheet: View {
    let item: PDFPreviewItem

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var isDocumentLoaded: Bool?

    private var canExportFromPreview: Bool {
        isDocumentLoaded == true
    }

    var body: some View {
        NavigationStack {
            PDFKitRepresentable(url: item.url, isDocumentLoaded: $isDocumentLoaded)
                .overlay {
                    if isDocumentLoaded == false {
                        ContentUnavailableView {
                            Label("Unable to Open PDF", systemImage: "doc.badge.exclamationmark")
                        } description: {
                            Text("This document could not be loaded. Try exporting again.")
                        }
                        .foregroundStyle(.white)
                    }
                }
                .background(CASERColors.inputBackground)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(CASERColors.card, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 12) {
                            Button {
                                saveTask = Task { await saveToPhotos() }
                            } label: {
                                if isSaving {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Photos", systemImage: "photo.on.rectangle.angled")
                                }
                            }
                            .disabled(isSaving || !canExportFromPreview)
                            .accessibilityLabel("Save to Photos")

                            Button {
                                showShareSheet = true
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .disabled(!canExportFromPreview)
                            .accessibilityLabel("Share PDF")
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .alert("Export", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let alertMessage {
                Text(alertMessage)
            }
        }
        .onDisappear {
            saveTask?.cancel()
            saveTask = nil
        }
    }

    @MainActor
    private func saveToPhotos() async {
        isSaving = true
        defer { isSaving = false }

        let result = await PDFPhotosSaver.saveToPhotos(url: item.url)
        switch result {
        case .success(let count):
            alertMessage = count == 1
                ? "Saved 1 page to Photos."
                : "Saved \(count) pages to Photos."
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
        showAlert = true
    }
}

private struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var isDocumentLoaded: Bool?

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(CASERColors.inputBackground)
        context.coordinator.load(
            url: url,
            into: pdfView,
            isDocumentLoaded: $isDocumentLoaded
        )
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if context.coordinator.requestedURL != url {
            context.coordinator.load(
                url: url,
                into: pdfView,
                isDocumentLoaded: $isDocumentLoaded
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.cancel()
        uiView.document = nil
    }

    @MainActor
    final class Coordinator {
        private final class LoadedDocument: @unchecked Sendable {
            let document: PDFDocument

            init(_ document: PDFDocument) {
                self.document = document
            }
        }

        private var loadTask: Task<Void, Never>?
        private(set) var requestedURL: URL?

        func load(
            url: URL,
            into pdfView: PDFView,
            isDocumentLoaded: Binding<Bool?>
        ) {
            cancel()
            requestedURL = url
            pdfView.document = nil
            isDocumentLoaded.wrappedValue = nil

            loadTask = Task { @MainActor [weak pdfView] in
                let worker = Task.detached(priority: .userInitiated) { () throws -> LoadedDocument? in
                    try Task.checkCancellation()
                    guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                        return nil
                    }
                    try Task.checkCancellation()
                    return LoadedDocument(document)
                }
                let result = await withTaskCancellationHandler {
                    await worker.result
                } onCancel: {
                    worker.cancel()
                }

                guard !Task.isCancelled, requestedURL == url else { return }
                let loaded: LoadedDocument?
                switch result {
                case .success(let value):
                    loaded = value
                case .failure:
                    loaded = nil
                }
                pdfView?.document = loaded?.document
                isDocumentLoaded.wrappedValue = loaded != nil
            }
        }

        func cancel() {
            loadTask?.cancel()
            loadTask = nil
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension View {
    func pdfPreviewSheet(item: Binding<PDFPreviewItem?>) -> some View {
        modifier(PDFPreviewModifier(item: item))
    }
}

private struct PDFPreviewModifier: ViewModifier {
    @Binding var item: PDFPreviewItem?
    @State private var activeItem: PDFPreviewItem?

    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: {
            activeItem?.removeTemporaryFileIfNeeded()
            activeItem = nil
        }) { previewItem in
            PDFPreviewSheet(item: previewItem)
                .onAppear { activeItem = previewItem }
        }
    }
}
