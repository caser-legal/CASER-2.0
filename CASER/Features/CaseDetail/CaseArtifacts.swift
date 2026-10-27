import SwiftUI
import UIKit

struct ArtifactSectionTitle: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.caserAccent)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct AboutCaseArtifact: View {
    let about: CaseAbout
    let artwork: MuseLoadState<Data>
    let onArtwork: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ArtifactSectionTitle(title: "About This Case", icon: "text.book.closed.fill")

            if case .loaded(let data) = artwork, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        Text("Artwork by Muse Image")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(8)
                    }
            }

            Text(about.story)
                .font(.body)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if case .idle = artwork {
                Button {
                    Task { await onArtwork() }
                } label: {
                    Label("Generate case artwork", systemImage: "photo.badge.plus")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.caserAccent)
                }
                .frame(minHeight: 44)
                .accessibilityHint("Uses Muse Image to create an illustration for this case")
            } else if case .loading = artwork {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Muse Image is creating artwork…")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

struct TimelineArtifact: View {
    let events: [CaseAbout.TimelineEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == events.count - 1 ? Color.caserAccent : Color.white.opacity(0.35))
                            .frame(width: 11, height: 11)
                            .padding(.top, 5)
                        if index < events.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDate(event.date))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.caserAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.caserAccent.opacity(0.14), in: Capsule())
                        Text(event.event)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, index == events.count - 1 ? 0 : 16)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func formattedDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

struct WhosWhoArtifact: View {
    let people: [CaseAbout.Person]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(people, id: \.self) { person in
                HStack(alignment: .top, spacing: 10) {
                    Text(initials(person.name))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(Color.caserAccent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(person.role)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

struct NewsArtifact: View {
    let items: [CaseAbout.NewsItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.outlet)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.caserAccent)
                    Text(item.summary)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct SourceCards: View {
    let citations: [MuseCitation]
    @State private var expanded = false

    private var visible: [MuseCitation] {
        expanded ? citations : Array(citations.prefix(3))
    }

    var body: some View {
        if !citations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ArtifactSectionTitle(title: "Sources", icon: "link")
                ForEach(visible, id: \.self) { citation in
                    Button {
                        guard let url = URLValidator.safeURL(citation.url), url.scheme?.lowercased() == "https" else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(Color.caserAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(citation.title)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if let host = URL(string: citation.url)?.host {
                                    Text(host)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.forward")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(12)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the source in Safari")
                }
                if citations.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(expanded ? "Show fewer sources" : "Show all \(citations.count) sources")
                                .font(.callout.weight(.semibold))
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(Color.caserAccent)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ThinkingArtifact: View {
    let thinking: String
    @State private var open = false

    var body: some View {
        if !thinking.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Atticus reasoning")
                            .font(.caption.weight(.semibold))
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(Color.caserAccent)
                    .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                if open {
                    Text(thinking)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct StreamingCursor: View {
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.caserAccent)
            .frame(width: 8, height: 16)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = false }
            }
            .accessibilityHidden(true)
    }
}
