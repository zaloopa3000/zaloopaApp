import SwiftUI

/// Экран с разноцветными шарами.
struct BallsView: View {
    @State private var simulation = BallSimulation()
    @State private var motion = MotionManager()
    @State private var haptics = ImpactHaptics()
    /// «Наклон», заданный пальцем, — запасной вариант там, где нет датчиков (симулятор, Mac).
    @State private var dragGravity: CGVector?
    /// Положение блока с гифкой в глобальных координатах — физика превращает его в препятствие.
    @State private var gifCardFrame: CGRect = .zero
    @Environment(\.scenePhase) private var scenePhase

    /// Доля высоты экрана, которую занимает блок с гифкой.
    private static let gifCardScreenFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { screen in
            ZStack(alignment: .top) {
                ballsLayer

                GIFCardView()
                    .frame(height: gifCardHeight(in: screen))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        gifCardFrame = frame
                    }
            }
        }
        // Фон всегда тёмный, поэтому строка состояния должна быть светлой и в светлой теме iOS.
        .preferredColorScheme(.dark)
        .onAppear {
            motion.start()
            haptics.prepare()
        }
        .onDisappear { motion.stop() }
        // Не держим датчики включёнными, пока приложение свёрнуто, — бережём батарею.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                motion.start()
                haptics.prepare()
            } else {
                motion.stop()
            }
        }
    }

    /// Высота блока с гифкой — половина всего экрана, включая зоны под Dynamic Island и полосой «домой».
    private func gifCardHeight(in screen: GeometryProxy) -> CGFloat {
        let fullScreenHeight = screen.size.height + screen.safeAreaInsets.top + screen.safeAreaInsets.bottom
        return fullScreenHeight * Self.gifCardScreenFraction
    }

    /// Шары на весь экран, включая зоны под Dynamic Island и полосой «домой».
    private var ballsLayer: some View {
        GeometryReader { proxy in
            // TimelineView перерисовывает Canvas каждый кадр экрана; в фоне анимация на паузе.
            TimelineView(.animation(paused: scenePhase != .active)) { timeline in
                Canvas { context, size in
                    // Границы физики берём ровно по размеру области рисования, чтобы «пол» и «стены»
                    // совпадали с краями экрана (размер из GeometryReader не учитывал зону под
                    // Dynamic Island и полосой «домой»).
                    if size != simulation.bounds {
                        simulation.configure(size: size)
                    }
                    simulation.cornerRadii = screenCornerRadii(from: proxy)
                    simulation.obstacle = gifCardObstacle(canvasOrigin: proxy.frame(in: .global).origin)
                    // Пока положение блока с гифкой неизвестно (первый кадр), шары не показываем,
                    // иначе они на мгновение появились бы на блоке и «перепрыгнули» под него.
                    guard simulation.obstacle != nil else { return }
                    // Наклон телефона; без датчиков — направление от пальца; по умолчанию — вниз.
                    simulation.targetGravity = motion.screenGravity ?? dragGravity ?? CGVector(dx: 0, dy: 1)
                    simulation.step(to: timeline.date)
                    haptics.handleWallImpact(speed: simulation.strongestWallImpactSpeed, at: timeline.date)
                    for ball in simulation.balls {
                        draw(ball, in: &context)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .ignoresSafeArea()
        .contentShape(.rect)
        .gesture(tiltByDragGesture, isEnabled: !motion.isAvailable)
    }

    /// Блок с гифкой как препятствие в координатах области рисования шаров.
    /// Сверху препятствие продлено за край экрана: иначе шары могли бы застрять
    /// в узкой полосе между блоком и Dynamic Island.
    private func gifCardObstacle(canvasOrigin: CGPoint) -> RoundedObstacle? {
        guard gifCardFrame.width > 0, gifCardFrame.height > 0 else { return nil }
        let card = gifCardFrame.offsetBy(dx: -canvasOrigin.x, dy: -canvasOrigin.y)
        let extensionAbove: CGFloat = 1000
        return RoundedObstacle(
            rect: CGRect(
                x: card.minX,
                y: card.minY - extensionAbove,
                width: card.width,
                height: card.height + extensionAbove
            ),
            cornerRadius: GIFCardView.cornerRadius
        )
    }

    /// Запасное управление без датчиков: тянете пальцем в сторону — туда и «наклоняется» экран.
    /// Направление сохраняется после того, как палец отпущен.
    private var tiltByDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                // Около 120 pt перетаскивания — полный «наклон»; дальше сила не растёт.
                let tilt = CGVector(dx: value.translation.width / 120, dy: value.translation.height / 120)
                let length = hypot(tilt.dx, tilt.dy)
                dragGravity = length > 1 ? CGVector(dx: tilt.dx / length, dy: tilt.dy / length) : tilt
            }
    }

    /// Радиус скругления экрана для iOS 26 и ниже, где системное API недоступно.
    /// Равен скруглению современных iPhone (на iPhone 17 системное API возвращает 62 pt);
    /// на моделях с меньшим скруглением шары просто останавливаются чуть раньше края.
    private static let fallbackPhoneCornerRadius: CGFloat = 62

    /// Скругления углов экрана, по которым шары должны скатываться, а не уходить за край.
    private func screenCornerRadii(from proxy: GeometryProxy) -> RectangleCornerRadii {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *), let radii = proxy.concentricCornerRadii {
            return radii
        }
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            let r = Self.fallbackPhoneCornerRadius
            return RectangleCornerRadii(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        }
        #endif
        return RectangleCornerRadii()
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
        let (circle, center) = squashedShape(of: ball, in: rect)

        // Градиент идёт через весь шар под индивидуальным углом.
        let dx = cos(ball.gradientAngle.radians) * ball.radius
        let dy = sin(ball.gradientAngle.radians) * ball.radius
        context.fill(
            circle,
            with: .linearGradient(
                Gradient(colors: ball.colors),
                startPoint: CGPoint(x: center.x - dx, y: center.y - dy),
                endPoint: CGPoint(x: center.x + dx, y: center.y + dy)
            )
        )

        // Мягкий блик сверху слева, плавно растворяющийся к краям.
        let highlightCenter = CGPoint(
            x: center.x - ball.radius * 0.35,
            y: center.y - ball.radius * 0.35
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

        // Вспышка после удара: шар светлеет изнутри (аддитивно, чтобы цвета не выцветали в серый).
        if ball.flash > 0.01 {
            var flashContext = context
            flashContext.blendMode = .plusLighter
            flashContext.fill(
                circle,
                with: .radialGradient(
                    Gradient(colors: [
                        .white.opacity(0.38 * ball.flash),
                        .white.opacity(0.12 * ball.flash)
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: ball.radius
                )
            )
        }

        // Тонкая полупрозрачная белая обводка по границе шара; во время вспышки она ярче.
        context.stroke(
            circle,
            with: .color(.white.opacity(0.15 + 0.5 * ball.flash)),
            lineWidth: 1
        )
    }

    /// Контур шара с учётом сплющивания после удара и центр этого контура.
    ///
    /// Шар сжимается вдоль направления удара и растягивается поперёк (площадь сохраняется),
    /// а центр смещается к точке контакта, чтобы сторона удара оставалась прижатой к стене или соседу.
    private func squashedShape(of ball: Ball, in rect: CGRect) -> (Path, CGPoint) {
        let circle = Path(ellipseIn: rect)
        guard ball.squash > 0.002 else { return (circle, ball.position) }

        let s = ball.squash
        let angle = ball.squashAngle
        let center = CGPoint(
            x: ball.position.x + cos(angle) * ball.radius * s,
            y: ball.position.y + sin(angle) * ball.radius * s
        )
        // Преобразования применяются справа налево: переносим центр шара в начало координат,
        // поворачиваем ось удара к оси X, сжимаем/растягиваем, поворачиваем обратно и ставим в новый центр.
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: angle)
            .scaledBy(x: 1 - s, y: 1 / (1 - s))
            .rotated(by: -angle)
            .translatedBy(x: -ball.position.x, y: -ball.position.y)
        return (circle.applying(transform), center)
    }
}

#Preview {
    BallsView()
}
