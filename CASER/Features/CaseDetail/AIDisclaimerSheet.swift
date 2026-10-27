import SwiftUI

struct AIDisclaimerSheet: View {
    var onAccept: () -> Void
    var onDecline: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                AIDisclaimerBody()
            }

            VStack(spacing: 12) {
                Text(consentStatement)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .tint(Color.caserAccent)
                    .multilineTextAlignment(.center)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    do {
                        try AIDisclaimerConsent.shared.accept()
                        onAccept()
                    } catch {
                        errorMessage = "Your acceptance couldn't be saved. Please try again."
                    }
                } label: {
                    Text("Accept")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.caserAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Agrees to the Atticus terms and records your acceptance")

                Button("Not Now", action: onDecline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .background(MainBackground())
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private var consentStatement: AttributedString {
        var text = AttributedString(AIDisclaimer.consentStatement)
        for (phrase, url) in [
            ("Privacy Policy", AIDisclaimer.privacyPolicyURL),
            ("Terms of Use", AIDisclaimer.termsURL),
            ("Accept", nil)
        ] {
            guard let range = text.range(of: phrase) else { continue }
            text[range].font = .footnote.bold()
            if let url, let link = URLValidator.safeURL(url) {
                text[range].link = link
                text[range].underlineStyle = .single
            }
        }
        return text
    }
}

struct AIDisclaimerBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "scale.3d")
                .font(.largeTitle)
                .foregroundStyle(Color.caserAccent)
                .accessibilityHidden(true)

            Text(AIDisclaimer.title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text(AIDisclaimer.intro)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(AIDisclaimer.points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.caserAccent)
                            .accessibilityHidden(true)
                        Text(point)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        AIDisclaimerSheet(onAccept: {}, onDecline: {})
    }
}
