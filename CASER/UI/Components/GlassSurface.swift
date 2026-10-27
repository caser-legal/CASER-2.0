import SwiftUI

extension View {
    func glassSurface(style: GlassStyle = .regular, shape: some InsettableShape = RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: Bool = false) -> some View {
        self.modifier(GlassSurfaceModifier(style: style, shape: AnyInsettableShape(shape), interactive: interactive))
    }
}

enum GlassStyle {
    case ultraThin, thin, regular, thick, clear
    
    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .clear: return .ultraThinMaterial
        }
    }
    
    func effectiveMaterial(reduceTransparency: Bool) -> Material {
        reduceTransparency ? .thickMaterial : material
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    let style: GlassStyle
    let shape: AnyInsettableShape
    let interactive: Bool
    
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    func body(content: Content) -> some View {
        content
            .background(style.effectiveMaterial(reduceTransparency: reduceTransparency), in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(shape)
            .if(interactive) { view in
                view
                    .hoverEffect(.highlight)
                    .scaleEffect(1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: interactive)
            }
    }
}

private struct AnyInsettableShape: InsettableShape {
    private let _path: @Sendable (CGRect) -> Path
    private let _inset: @Sendable (CGFloat) -> AnyInsettableShape
    
    init<S: InsettableShape>(_ shape: S) {
        _path = { rect in shape.path(in: rect) }
        _inset = { amount in AnyInsettableShape(shape.inset(by: amount)) }
    }
    
    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
    
    func inset(by amount: CGFloat) -> AnyInsettableShape {
        _inset(amount)
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
