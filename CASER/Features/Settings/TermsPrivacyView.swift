import SwiftUI

struct TermsPrivacyView: View {
    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Terms of Service")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text("Last Updated: October 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "1. Acceptance of Terms")
                        SectionBody(text: "By accessing and using \(AppBranding.legalReference), you accept and agree to be bound by these Terms of Service. If you do not agree, do not use this application.")
                        
                        SectionHeader(title: "2. Service Description")
                        SectionBody(text: "CASER provides access to federal district and bankruptcy case filings through search functionality, keyword monitoring alerts, AI-generated case insights (Atticus), and case management tools. All features are available free of charge, with no subscriptions or in-app purchases.")
                        
                        SectionHeader(title: "3. Legal Disclaimer")
                        SectionBody(text: "CASER does not provide legal advice. This application is a monitoring and research tool only. Atticus insights and answers are information only, not legal advice, and may be inaccurate or incomplete. You should not rely on CASER as a substitute for professional legal counsel. Always consult with a qualified attorney for legal advice specific to your situation.")
                        
                        SectionHeader(title: "4. No Warranty on Accuracy")
                        SectionBody(text: "While we strive for accuracy, CASER makes no warranties regarding the completeness, accuracy, or timeliness of case information, search results, or alert notifications. Case filings may be delayed, incomplete, or contain errors. Always verify critical information with official court records.")
                        
                        SectionHeader(title: "5. Alert System Limitations")
                        SectionBody(text: "The keyword alert system checks for new filings on a regular schedule but may experience delays or miss filings due to technical issues, court publishing delays, or system maintenance. Do not rely solely on CASER alerts for time-sensitive legal matters.")
                        
                        SectionHeader(title: "6. User Responsibilities")
                        SectionBody(text: "You are responsible for: (a) maintaining the confidentiality of your account credentials, (b) all activities under your account, (c) ensuring your use complies with applicable laws, and (d) verifying all case information with official sources.")
                        
                        SectionHeader(title: "7. Acceptable Use")
                        SectionBody(text: "You may not: (a) share your account with others, (b) use automated systems to scrape or download bulk data, (c) reverse engineer the application, (d) use the service for any unlawful purpose, or (e) interfere with the service's operation.")
                        
                        SectionHeader(title: "8. Search Fees and Savings Tracker")
                        SectionBody(text: "Searching cases and accessing PACER document links through CASER incurs no per-search or per-result fees. The 'PACER Savings Tracker' shows what you would have paid on PACER's uncapped search-result screens ($0.10 per result, with no $3 document cap on those screens) if you had used their system instead. The tracker is informational only and does not represent actual PACER bills.")
                        
                        SectionHeader(title: "9. Account Termination")
                        SectionBody(text: "We reserve the right to suspend or terminate accounts that violate these terms or engage in fraudulent activity. You may terminate your account at any time by contacting \(AppBranding.supportEmail).")
                        
                        SectionHeader(title: "10. Limitation of Liability")
                        SectionBody(text: "CASER and its operators shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of the service, including but not limited to missed filings, inaccurate information, or service interruptions.")
                        
                        SectionHeader(title: "11. Changes to Terms")
                        SectionBody(text: "We reserve the right to modify these terms at any time. Continued use of the service after changes constitutes acceptance of the modified terms. Material changes will be communicated via email.")
                    }
                }
                
                Divider()
                    .background(.white.opacity(0.2))
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Privacy Policy")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text("Last Updated: October 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "1. Information We Collect")
                        SectionBody(text: "Usage Data: Search queries, keyword monitors, saved cases, search history, and usage statistics (search counts, monitor matches, pages viewed) are stored locally on your device. When you open a case's Details, the case details you open and any follow-up questions you ask Atticus are sent to Meta through CASER's server (see Sections 4 and 6).")
                        SectionBody(text: "Technical Data: Device type, iOS version, app version, and performance metrics.")
                        
                        SectionHeader(title: "2. How We Use Your Information")
                        SectionBody(text: "We use collected information to: (a) provide and maintain the service, (b) process searches and deliver alerts, (c) track PACER savings, (d) improve service performance and features, (e) provide Atticus case insights, and (f) ensure security.")
                        
                        SectionHeader(title: "3. Data Storage and Security")
                        SectionBody(text: "Your data is protected using: (a) iOS Keychain for sensitive data, (b) TLS encryption for network requests, and (c) local storage with iOS data protection. Search history and settings remain on your device.")
                        
                        SectionHeader(title: "4. Third-Party Services")
                        SectionBody(text: "We use the following third-party services: Meta's Muse AI, reached through CASER's server, to generate Atticus case insights and answers; Apple's User Notifications framework for scheduling on-device alert delivery. These services have their own privacy policies and data handling practices.")
                        
                        SectionHeader(title: "5. Data Sharing")
                        SectionBody(text: "We do not sell, rent, or share your personal information with third parties for marketing purposes. We may share data only: (a) with service providers necessary to operate the application, (b) when required by law or legal process, (c) to protect our rights or prevent fraud, or (d) with your explicit consent.")
                        
                        SectionHeader(title: "6. AI Features")
                        SectionBody(text: "Atticus insights on a case's Details page and answers to your follow-up questions are generated by Meta's Muse AI. To produce them, the case details you open and the questions you ask are sent to Meta through CASER's server. CASER does not send your saved cases, alerts, or search history. Do not enter confidential, privileged, or sensitive personal information.")
                        SectionBody(text: "Atticus output is information only, not legal advice. AI-generated content can be wrong, incomplete, or out of date; verify anything important with official court records and a licensed attorney.")
                        
                        SectionHeader(title: "7. Push Notifications")
                        SectionBody(text: "If you enable notifications for case alerts, alerts are scheduled locally on your device using Apple's notification APIs. CASER does not send alert notifications from its servers. Lock-screen text uses a generic message; matched keywords are available inside the app when you open the notification. You can disable notifications at any time in iOS Settings.")
                        
                        SectionHeader(title: "8. Data Retention")
                        SectionBody(text: "App data is stored locally on your device and retained until you delete it. Search history, saved cases, alerts, and settings can be cleared from within the app. A record of your acceptance of the Atticus terms is kept on your device.")
                        
                        SectionHeader(title: "9. Your Rights")
                        SectionBody(text: "You have the right to: (a) access your personal data, (b) correct inaccurate data, (c) request deletion of your data, (d) export your data, (e) opt-out of non-essential communications, and (f) withdraw consent for data processing. Contact \(AppBranding.supportEmail) to exercise these rights.")
                        
                        SectionHeader(title: "10. Children's Privacy")
                        SectionBody(text: "CASER is not intended for users under 18 years of age. We do not knowingly collect information from children. If you believe a child has provided information, contact us immediately.")
                        
                        SectionHeader(title: "11. California Privacy Rights")
                        SectionBody(text: "California residents have additional rights under CCPA, including the right to know what personal information is collected, the right to delete personal information, and the right to opt-out of sale (we do not sell personal information).")
                        
                        SectionHeader(title: "12. Changes to Privacy Policy")
                        SectionBody(text: "We may update this privacy policy periodically. Material changes will be communicated via email. Continued use after changes constitutes acceptance of the updated policy.")
                        
                        SectionHeader(title: "13. Contact Information")
                        SectionBody(text: "For privacy-related questions, data requests, or to exercise your rights, contact us at: \(AppBranding.supportEmail)")
                    }
                }
            }
            .padding(24)
            .glassSurface(style: .regular, shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background {
            MainBackground()
        }
        .navigationTitle("Terms & Privacy")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.top, 4)
    }
}

private struct SectionBody: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.85))
    }
}
