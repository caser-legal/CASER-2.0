import SwiftUI

extension View {
    @ViewBuilder
    func caserScrollBounce() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}