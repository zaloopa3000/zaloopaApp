import SwiftUI

/// Один шар на экране.
struct Ball: Identifiable {
    let id = UUID()
    /// Центр шара в координатах экрана.
    var position: CGPoint
    /// Скорость в точках в секунду.
    var velocity: CGVector = .zero
    /// Радиус шара.
    var radius: CGFloat
    /// Цвета градиента внутри шара (2–3 сочетающихся оттенка).
    var colors: [Color]
    /// Направление градиента — у каждого шара своё, чтобы они не выглядели одинаково.
    var gradientAngle: Angle
    /// Яркость вспышки при ударе (0...1), затухает со временем.
    var flash: Double = 0
}
