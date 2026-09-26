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

    /// Наборы сочетающихся цветов: соседние оттенки на цветовом круге дают мягкие переходы.
    private let palettes: [[Color]] = [
        // Закат: персиковый → розовый → сиреневый
        [Color(hue: 0.07, saturation: 0.55, brightness: 1.0),
         Color(hue: 0.95, saturation: 0.50, brightness: 0.98),
         Color(hue: 0.80, saturation: 0.45, brightness: 0.95)],
        // Океан: бирюзовый → голубой → фиолетовый
        [Color(hue: 0.50, saturation: 0.50, brightness: 0.98),
         Color(hue: 0.60, saturation: 0.55, brightness: 0.98),
         Color(hue: 0.73, saturation: 0.45, brightness: 0.95)],
        // Сияние: мятный → небесный → лавандовый
        [Color(hue: 0.42, saturation: 0.45, brightness: 0.95),
         Color(hue: 0.56, saturation: 0.45, brightness: 1.0),
         Color(hue: 0.76, saturation: 0.35, brightness: 1.0)],
        // Ягоды: розовый → пурпурный → индиго
        [Color(hue: 0.94, saturation: 0.50, brightness: 1.0),
         Color(hue: 0.86, saturation: 0.50, brightness: 0.92),
         Color(hue: 0.70, saturation: 0.50, brightness: 0.90)],
        // Цитрус: лимонный → персиковый → коралловый
        [Color(hue: 0.14, saturation: 0.45, brightness: 1.0),
         Color(hue: 0.07, saturation: 0.50, brightness: 1.0),
         Color(hue: 0.99, saturation: 0.50, brightness: 0.98)],
        // Лагуна: аква → бирюзовый → мятный
        [Color(hue: 0.53, saturation: 0.45, brightness: 1.0),
         Color(hue: 0.47, saturation: 0.50, brightness: 0.92),
         Color(hue: 0.38, saturation: 0.40, brightness: 0.95)]
    ]

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
            let colors = palettes.randomElement() ?? palettes[0]
            result.append(Ball(
                position: position,
                radius: radius,
                colors: colors,
                gradientAngle: .degrees(Double.random(in: 0..<360))
            ))
        }
        return result
    }
}
