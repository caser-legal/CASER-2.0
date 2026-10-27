import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage = 0

    private let pageCount = 5
    
    var body: some View {
        ZStack {
            OnboardingAnimatedBackground()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if currentPage < pageCount - 1 {
                        Button("Skip") {
                            hasCompletedOnboarding = true
                            dismiss()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .frame(minHeight: 44)
                
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    problemPage.tag(1)
                    solutionPage.tag(2)
                    atticusPage.tag(3)
                    getStartedPage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        ForEach(0..<pageCount, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? (currentPage == pageCount - 1 ? Color.caserGreen : Color.white.opacity(0.6)) : Color.white.opacity(0.2))
                                .frame(width: i == currentPage ? 24 : 8, height: 8)
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentPage)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")

                    Button {
                        if currentPage < pageCount - 1 {
                            if reduceMotion {
                                currentPage += 1
                            } else {
                                withAnimation { currentPage += 1 }
                            }
                        } else {
                            hasCompletedOnboarding = true
                            dismiss()
                        }
                    } label: {
                        Text(currentPage < pageCount - 1 ? "Continue" : "Enter CASER")
                            .font(.system(.headline, design: currentPage == pageCount - 1 ? .serif : .default))
                            .tracking(currentPage == pageCount - 1 ? 1.5 : 0)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 55)
                            .background(currentPage == pageCount - 1 ? Color.caserGreen : Color(white: 0.28))
                            .foregroundStyle(currentPage == pageCount - 1 ? Color.black : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentPage)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var welcomePage: some View {
        scrollablePage { pageHeight in
            VStack(spacing: 0) {
                Spacer()

                BrandAccretionHero(
                    logoHeight: 148 * welcomeHeroScale(pageHeight),
                    diskSize: 300 * welcomeHeroScale(pageHeight),
                    playLaunchAnimation: true,
                    showsTagline: true
                )

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private var problemPage: some View {
        scrollablePage { pageHeight in
            VStack(spacing: 0) {
                Spacer().frame(height: 16)

                BrandAccretionHero(
                    logoHeight: 100 * heroScale(pageHeight),
                    diskSize: 220 * heroScale(pageHeight)
                )
                .frame(height: 220 * heroScale(pageHeight))
                .padding(.bottom, 12)

                Text("The PACER Problem")
                    .font(.system(.title, design: .serif).bold())
                    .tracking(0.5)
                    .padding(.bottom, 8)

                Text("The federal court system charges for public record access")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                VStack(spacing: 14) {
                    problemRow(stat: "$0.10", text: "per page — surprise charges on every search")
                    problemRow(stat: "1990s", text: "interface — outdated and unusable")
                    problemRow(stat: "Zero", text: "keyword search — only case numbers work")
                    problemRow(stat: "$142M", text: "per year — a monopoly on public records")
                }
                .padding(20)
                .glassSurface(style: .thin)
                .padding(.horizontal, 24)

                Spacer()

                Text("PACER charges 1,109× more than cloud storage costs for the same data.")
                    .font(.system(.caption, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        }
    }
    
    private var solutionPage: some View {
        scrollablePage { pageHeight in
            VStack(spacing: 0) {
                Spacer().frame(height: 16)

                BrandAccretionHero(
                    logoHeight: 100 * heroScale(pageHeight),
                    diskSize: 220 * heroScale(pageHeight)
                )
                .frame(height: 220 * heroScale(pageHeight))
                .padding(.bottom, 12)

                Text("CASER Solves This")
                    .font(.system(.title, design: .serif).bold())
                    .tracking(0.5)
                    .padding(.bottom, 8)

                Text("Monitor every federal court without paying search fees")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                VStack(spacing: 12) {
                    solutionRow(icon: "building.columns.fill", text: "170+ federal courts monitored")
                    solutionRow(icon: "bell.badge.fill", text: "Notifications when new filings match your keywords")
                    solutionRow(icon: "doc.text.fill", text: "Direct links to court documents")
                    solutionRow(icon: "person.fill.xmark", text: "No PACER account required")
                }
                .padding(20)
                .glassSurface(style: .thin)
                .padding(.horizontal, 24)

                Spacer()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 32) {
                        miniStat(value: "323K+", label: "Docs Monitored\nFirst 3 Days")
                        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 36)
                        miniStat(value: "$100K", label: "PACER Fees\nSaved Daily")
                    }

                    VStack(spacing: 12) {
                        miniStat(value: "323K+", label: "Docs Monitored — First 3 Days")
                        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 72, height: 1)
                        miniStat(value: "$100K", label: "PACER Fees Saved Daily")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
    }
    
    private var atticusPage: some View {
        scrollablePage { pageHeight in
            VStack(spacing: 0) {
                Spacer().frame(height: 16)

                BrandAccretionHero(
                    logoHeight: 100 * heroScale(pageHeight),
                    diskSize: 220 * heroScale(pageHeight)
                )
                .frame(height: 220 * heroScale(pageHeight))
                .padding(.bottom, 12)

                Text("Meet Atticus")
                    .font(.system(.title, design: .serif).bold())
                    .tracking(0.5)
                    .padding(.bottom, 8)

                Text("Your AI Legal Research Assistant")
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(Color.caserAccent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 14) {
                    atticusRow(icon: "book.fill", text: "Research legal concepts, statutes & precedent")
                    atticusRow(icon: "text.magnifyingglass", text: "Define terms and explain legal structures")
                    atticusRow(icon: "arrow.triangle.branch", text: "Connect principles across areas of law")
                    atticusRow(icon: "doc.plaintext.fill", text: "Summarize complex legal texts")
                    atticusRow(icon: "scale.3d", text: "Neutral information — never legal advice")
                }
                .padding(20)
                .glassSurface(style: .thin)
                .padding(.horizontal, 24)

                Spacer()

                Text("Powered by Meta Muse")
                    .font(.system(.caption, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        }
    }
    
    private var getStartedPage: some View {
        scrollablePage { pageHeight in
            VStack(spacing: 0) {
                Spacer().frame(height: 16)

                BrandAccretionHero(
                    logoHeight: 100 * heroScale(pageHeight),
                    diskSize: 220 * heroScale(pageHeight)
                )
                .frame(height: 220 * heroScale(pageHeight))
                .padding(.bottom, 12)

                Text("Everything in One Place")
                    .font(.system(.title, design: .serif).bold())
                    .tracking(0.5)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                Text(AppBranding.fullName)
                    .font(.system(.caption, design: .serif).weight(.medium))
                    .foregroundStyle(Color.caserAccent)
                    .tracking(0.5)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                VStack(spacing: 12) {
                    featureRow(icon: "magnifyingglass", title: "Search", desc: "Federal court records across all jurisdictions")
                    featureRow(icon: "bell.badge.fill", title: "Monitor", desc: "Notifications on new filings that match your keywords")
                    featureRow(icon: "brain.head.profile.fill", title: "Atticus AI", desc: "Intelligent legal research assistant")
                    featureRow(icon: "dollarsign.circle.fill", title: "Save", desc: "Track PACER fees you've avoided")
                }
                .padding(20)
                .glassSurface(style: .thin)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }
    
    private func heroScale(_ pageHeight: CGFloat) -> CGFloat {
        min(1, max(0.4, (pageHeight - 470) / 220))
    }

    private func welcomeHeroScale(_ pageHeight: CGFloat) -> CGFloat {
        min(1, max(0.5, (pageHeight - 120) / 300))
    }

    private func scrollablePage<Content: View>(
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                content(geometry.size.height)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
            }
        }
    }
    
    private func problemRow(stat: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(stat)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(.red.opacity(0.85))
                .frame(minWidth: 52, alignment: .trailing)
            Text(text)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
    
    private func solutionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.caserGreen)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
    
    private func atticusRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.caserAccent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
    
    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced).bold())
                .foregroundStyle(Color.caserGreen)
            Text(label)
                .font(.system(.caption2, design: .serif))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
    
    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.caserGreen)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                Text(desc)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
