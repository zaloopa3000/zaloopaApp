import SwiftUI

/// Экран с разноцветными шарами.
struct BallsView: View {
    @State private var simulation = BallSimulation()

    var body: some View {
        Canvas { context, _ in
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

    /// Рисует шар: многоцветный градиент, мягкий блик для объёма и тонкую белую обводку.
    private func draw(_ ball: Ball, in context: inout GraphicsContext) {
        let rect = CGRect(
            x: ball.position.x - ball.radius,
            y: ball.position.y - ball.radius,
            width: ball.radius * 2,
            height: ball.radius * 2
        )
        let circle = Path(ellipseIn: rect)

        // Градиент идёт через весь шар под индивидуальным углом.
        let dx = cos(ball.gradientAngle.radians) * ball.radius
        let dy = sin(ball.gradientAngle.radians) * ball.radius
        context.fill(
            circle,
            with: .linearGradient(
                Gradient(colors: ball.colors),
                startPoint: CGPoint(x: ball.position.x - dx, y: ball.position.y - dy),
                endPoint: CGPoint(x: ball.position.x + dx, y: ball.position.y + dy)
            )
        )

        // Мягкий блик сверху слева, плавно растворяющийся к краям.
        let highlightCenter = CGPoint(
            x: ball.position.x - ball.radius * 0.35,
            y: ball.position.y - ball.radius * 0.35
        )
        context.fill(
            circle,
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.35), .white.opacity(0)]),
                center: highlightCenter,
                startRadius: 0,
                endRadius: ball.radius * 1.1
            )
        )

        // Тонкая полупрозрачная белая обводка по границе шара.
        context.stroke(
            circle,
            with: .color(.white.opacity(0.15)),
            lineWidth: 1
        )
    }
}

#Preview {
    BallsView()
}
