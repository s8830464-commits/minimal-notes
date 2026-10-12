import SwiftUI

/// Фирменные пружинные анимации в стиле Apple iOS
struct AppleSpringButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.90
    var opacity: Double = 0.85

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? opacity : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension View {
    /// Удобный модификатор для плавной тактильной пружины
    func appleSpringPress(scale: CGFloat = 0.92) -> some View {
        self.buttonStyle(AppleSpringButtonStyle(scale: scale))
    }
}
