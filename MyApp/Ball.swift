import SwiftUI

/// Один светящийся шар на экране.
struct Ball: Identifiable {
    let id = UUID()
    /// Центр шара в координатах экрана.
    var position: CGPoint
    /// Скорость в точках в секунду.
    var velocity: CGVector = .zero
    /// Радиус «тела» шара (без учёта мягкого ореола).
    var radius: CGFloat
    /// Оттенок цвета шара (0...1).
    var hue: Double
    /// Яркость вспышки при ударе (0...1), затухает со временем.
    var flash: Double = 0
}
