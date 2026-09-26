import SwiftUI

/// Хранит состояние всех шаров и (на следующих этапах) считает их физику.
@Observable
final class BallSimulation {
    /// Количество шаров на экране.
    let ballCount = 40
    /// Диапазон радиусов шаров в точках.
    let radiusRange: ClosedRange<CGFloat> = 10...20

    private(set) var balls: [Ball] = []
    private(set) var bounds: CGSize = .zero

    /// Мягкая пастельная палитра оттенков: розовый, сиреневый, голубой, бирюзовый, персиковый.
    private let palette: [Double] = [0.92, 0.78, 0.60, 0.50, 0.08]

    /// Вызывается при появлении экрана и при изменении его размера.
    func configure(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let isFirstLayout = balls.isEmpty
        bounds = size
        if isFirstLayout {
            balls = makeBalls(in: size)
        } else {
            // При изменении размера просто возвращаем шары в пределы экрана.
            for index in balls.indices {
                let r = balls[index].radius
                balls[index].position.x = min(max(balls[index].position.x, r), size.width - r)
                balls[index].position.y = min(max(balls[index].position.y, r), size.height - r)
            }
        }
    }

    /// Раскладывает шары случайно, стараясь избегать перекрытий.
    private func makeBalls(in size: CGSize) -> [Ball] {
        var result: [Ball] = []
        let spacing: CGFloat = 4

        for _ in 0..<ballCount {
            let radius = CGFloat.random(in: radiusRange)
            var position = CGPoint.zero
            // Несколько попыток найти свободное место; если не нашли — берём последнюю.
            for _ in 0..<50 {
                position = CGPoint(
                    x: CGFloat.random(in: radius...(size.width - radius)),
                    y: CGFloat.random(in: radius...(size.height - radius))
                )
                let overlaps = result.contains { other in
                    hypot(other.position.x - position.x, other.position.y - position.y)
                        < other.radius + radius + spacing
                }
                if !overlaps { break }
            }
            let baseHue = palette.randomElement() ?? 0.6
            let hue = (baseHue + Double.random(in: -0.04...0.04) + 1).truncatingRemainder(dividingBy: 1)
            result.append(Ball(position: position, radius: radius, hue: hue))
        }
        return result
    }
}
