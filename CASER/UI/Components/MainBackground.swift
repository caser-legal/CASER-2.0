import SwiftUI

struct MainBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Image("main-background")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .clipped()
        }
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    MainBackground()
}
