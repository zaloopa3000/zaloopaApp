import SwiftUI

/// Экран со светящимися шарами.
struct BallsView: View {
    @State private var simulation = BallSimulation()

    var body: some View {
        Canvas { context, _ in
            // Лёгкое общее размытие делает края шаров ещё мягче.
            context.addFilter(.blur(radius: 1.5))
            // Аддитивное смешивание: там, где шары рядом, свечение складывается.
            context.blendMode = .plusLighter

            for ball in simulation.balls {
                draw(ball, in: &context)
            }
        }
        .background(background)
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            simulation.configure(size: size)
        }
    }

    /// Тёмный фон с едва заметным градиентом.
    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.01, green: 0.01, blue: 0.04)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    /// Рисует один шар: светлая сердцевина → насыщенный цвет → прозрачный ореол.
    private func draw(_ ball: Ball, in context: inout GraphicsContext) {
        // Ореол выходит за пределы «тела» шара, чтобы край растворялся.
        let glowRadius = ball.radius * 1.6
        let rect = CGRect(
            x: ball.position.x - glowRadius,
            y: ball.position.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        )

        let core = Color(hue: ball.hue, saturation: 0.15, brightness: 1.0)
        let body = Color(hue: ball.hue, saturation: 0.55, brightness: 0.95)

        // Доля радиуса ореола, где заканчивается «тело» шара.
        let edge = ball.radius / glowRadius
        let gradient = Gradient(stops: [
            .init(color: core.opacity(0.95), location: 0),
            .init(color: body.opacity(0.85), location: edge * 0.55),
            .init(color: body.opacity(0.45), location: edge),
            .init(color: body.opacity(0.0), location: 1)
        ])

        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                gradient,
                center: ball.position,
                startRadius: 0,
                endRadius: glowRadius
            )
        )
    }
}

#Preview {
    BallsView()
}
