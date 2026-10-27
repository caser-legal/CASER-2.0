import SwiftUI

struct PDFExportTrigger: View {
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: "doc.richtext")
                .font(.caption)
                .foregroundStyle(isEnabled ? .white.opacity(0.85) : .white.opacity(0.4))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .accessibilityLabel(isEnabled ? "Preview and export PDF" : "PDF export unavailable")
    }
}