import SwiftUI

/// Твёрдое препятствие на экране — прямоугольник со скруглёнными углами (блок с гифкой).
struct RoundedObstacle: Equatable {
    var rect: CGRect
    var cornerRadius: CGFloat
}

/// Хранит состояние всех шаров и считает их физику.
///
/// Намеренно не `@Observable`: экран и так перерисовывается каждый кадр через `TimelineView`,
/// а шаг физики выполняется прямо перед отрисовкой — лишние инвалидации SwiftUI не нужны.
final class BallSimulation {
    /// Количество шаров на экране.
    let ballCount = 40
    /// Диапазон радиусов шаров в точках.
    let radiusRange: ClosedRange<CGFloat> = 13...27

    // MARK: - Параметры физики

    /// Ускорение от «наклона» в точках/с² для шара среднего размера.
    let gravityStrength: CGFloat = 1300
    /// Вязкое трение (1/с) для шара среднего размера: лёгкое сопротивление «воздуха», сглаживающее движение.
    let drag: CGFloat = 0.35
    /// Радиус «среднего» шара, относительно которого масштабируются ускорение и трение.
    let referenceRadius: CGFloat = 20
    /// Предохранитель от слишком быстрого движения в точках/с (обычно не достигается).
    let maxSpeed: CGFloat = 2200
    /// Максимальная длительность одного шага физики. Быстрые шары считаются несколькими
    /// мелкими шагами за кадр, чтобы не проскакивать друг сквозь друга.
    let maxSubstep: CGFloat = 1.0 / 120.0
    /// Упругость отскока от стен: доля скорости, которая сохраняется после удара.
    let wallRestitution: CGFloat = 0.55
    /// Скорость удара, ниже которой шар не отскакивает, а просто прилипает к стене (убирает дрожание).
    /// Должна быть заметно больше скорости, которую самый тяжёлый шар набирает за один шаг физики.
    let restingSpeed: CGFloat = 40
    /// Упругость столкновений шаров между собой.
    let ballRestitution: CGFloat = 0.6
    /// Сколько раз за кадр разрешаем столкновения: несколько проходов нужны, чтобы плотная куча не проседала.
    let collisionIterations = 6

    // MARK: - Параметры сплющивания

    /// Максимальное сплющивание шара (доля радиуса), чтобы даже сильный удар выглядел аккуратно.
    let maxSquash: CGFloat = 0.15
    /// Скорость удара (pt/с), при которой шар сплющивается до максимума.
    let fullSquashImpactSpeed: CGFloat = 1400
    /// За сколько секунд шар возвращает круглую форму (время затухания).
    let squashRecoveryTime: CGFloat = 0.09

    // MARK: - Параметры вспышек

    /// Скорость удара (pt/с), ниже которой шар не вспыхивает — чтобы лёгкие касания не мерцали.
    let flashThresholdSpeed: CGFloat = 150
    /// Скорость удара (pt/с), при которой вспышка максимальная.
    let fullFlashImpactSpeed: CGFloat = 1000
    /// Время затухания вспышки в секундах.
    let flashFadeTime: CGFloat = 0.3

    /// Желаемая «гравитация» от наклона телефона: направление и сила (длина 0…1).
    /// Задаётся снаружи каждый кадр; физика плавно подтягивает к ней `gravityDirection`.
    var targetGravity = CGVector(dx: 0, dy: 1)
    /// Время сглаживания наклона в секундах: убирает дрожание датчика и резкие рывки.
    let gravitySmoothingTime: CGFloat = 0.12
    /// Текущая сглаженная «гравитация», по которой считается движение.
    var gravityDirection = CGVector(dx: 0, dy: 1)
    /// Радиусы скругления углов экрана: в углах шары катятся по дуге, а не уходят за край.
    var cornerRadii = RectangleCornerRadii()
    /// Препятствие, которое шары обтекают и о которое бьются. Когда оно появляется или
    /// меняется, шары, оказавшиеся внутри, переносятся под него.
    var obstacle: RoundedObstacle? {
        didSet {
            if obstacle != oldValue { moveBallsOutOfObstacle() }
        }
    }

    private(set) var balls: [Ball] = []
    private(set) var bounds: CGSize = .zero
    /// Скорость самого сильного удара о стену за последний вызов `step(to:)` — для тактильного отклика.
    private(set) var strongestWallImpactSpeed: CGFloat = 0
    private var lastStepDate: Date?

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

    // MARK: - Шаг симуляции

    /// Продвигает симуляцию до момента `date`. Вызывается один раз за кадр.
    func step(to date: Date) {
        defer { lastStepDate = date }
        strongestWallImpactSpeed = 0
        guard let lastStepDate, bounds.width > 0 else { return }
        // Ограничиваем шаг, чтобы после паузы (например, сворачивания приложения) шары не «телепортировались».
        let dt = CGFloat(min(max(date.timeIntervalSince(lastStepDate), 0), 1.0 / 30.0))
        guard dt > 0 else { return }

        // Плавно подтягиваем гравитацию к наклону телефона (экспоненциальное сглаживание,
        // не зависящее от частоты кадров).
        let smoothing = 1 - exp(-dt / gravitySmoothingTime)
        gravityDirection.dx += (targetGravity.dx - gravityDirection.dx) * smoothing
        gravityDirection.dy += (targetGravity.dy - gravityDirection.dy) * smoothing

        let substeps = max(1, Int((dt / maxSubstep).rounded(.up)))
        let substepDuration = dt / CGFloat(substeps)
        for _ in 0..<substeps {
            advance(by: substepDuration)
        }
    }

    /// Один шаг физики: движение, стены и столкновения шаров.
    private func advance(by dt: CGFloat) {
        let squashDecay = exp(-dt / squashRecoveryTime)
        let flashDecay = Double(exp(-dt / flashFadeTime))

        for index in balls.indices {
            var ball = balls[index]

            // Шар быстро возвращается к круглой форме после удара, вспышка плавно гаснет.
            ball.squash *= squashDecay
            ball.flash *= flashDecay

            // Чем больше шар, тем он «тяжелее»: сильнее разгоняется и меньше тормозится средой,
            // поэтому быстрее набирает скорость и едет быстрее. Маленькие — лёгкие и отстают.
            let sizeFactor = ball.radius / referenceRadius
            let gravity = gravityStrength * sizeFactor
            let acceleration = CGVector(
                dx: gravityDirection.dx * gravity,
                dy: gravityDirection.dy * gravity
            )
            let damping = exp(-drag / sizeFactor * dt)

            // Скорость: ускорение от наклона + вязкое затухание + предел скорости.
            ball.velocity.dx = (ball.velocity.dx + acceleration.dx * dt) * damping
            ball.velocity.dy = (ball.velocity.dy + acceleration.dy * dt) * damping
            let speed = hypot(ball.velocity.dx, ball.velocity.dy)
            if speed > maxSpeed {
                ball.velocity.dx *= maxSpeed / speed
                ball.velocity.dy *= maxSpeed / speed
            }

            ball.position.x += ball.velocity.dx * dt
            ball.position.y += ball.velocity.dy * dt

            resolveWallCollisions(for: &ball)
            balls[index] = ball
        }

        // Шары расталкивают друг друга; после каждого прохода снова не пускаем их за стены,
        // иначе соседи могли бы «выдавить» шар за край экрана.
        for _ in 0..<collisionIterations {
            resolveBallCollisions()
            for index in balls.indices {
                resolveWallCollisions(for: &balls[index])
            }
        }
    }

    /// Раздвигает пересекающиеся шары и обменивает их скорости по законам упругого удара с учётом массы.
    private func resolveBallCollisions() {
        let count = balls.count
        for i in 0..<count {
            for j in (i + 1)..<count {
                let dx = balls[j].position.x - balls[i].position.x
                let dy = balls[j].position.y - balls[i].position.y
                let minDistance = balls[i].radius + balls[j].radius
                let distanceSquared = dx * dx + dy * dy
                guard distanceSquared < minDistance * minDistance else { continue }

                // Нормаль удара — направление от центра i к центру j.
                // Если центры совпали, берём произвольное направление, чтобы не делить на ноль.
                let distance = sqrt(distanceSquared)
                let normal = distance > 0.0001
                    ? CGVector(dx: dx / distance, dy: dy / distance)
                    : CGVector(dx: 1, dy: 0)

                // Лёгкий шар сдвигается сильнее, тяжёлый — слабее.
                let inverseMassI = 1 / balls[i].mass
                let inverseMassJ = 1 / balls[j].mass
                let inverseMassSum = inverseMassI + inverseMassJ

                let overlap = minDistance - distance
                let shareI = overlap * inverseMassI / inverseMassSum
                let shareJ = overlap * inverseMassJ / inverseMassSum
                balls[i].position.x -= normal.dx * shareI
                balls[i].position.y -= normal.dy * shareI
                balls[j].position.x += normal.dx * shareJ
                balls[j].position.y += normal.dy * shareJ

                // Скорость сближения вдоль нормали; если шары уже расходятся — импульс не нужен.
                let approachSpeed = (balls[j].velocity.dx - balls[i].velocity.dx) * normal.dx
                    + (balls[j].velocity.dy - balls[i].velocity.dy) * normal.dy
                guard approachSpeed < 0 else { continue }

                // Сплющиваем оба шара вдоль линии удара; лёгкий шар деформируется сильнее тяжёлого.
                let impactAngle = atan2(normal.dy, normal.dx)
                let massSum = balls[i].mass + balls[j].mass
                registerImpact(on: &balls[i], speed: -approachSpeed * 2 * balls[j].mass / massSum, angle: impactAngle)
                registerImpact(on: &balls[j], speed: -approachSpeed * 2 * balls[i].mass / massSum, angle: impactAngle + .pi)

                // Слабые касания (шары лежат друг на друге) гасим без отскока — так куча не дрожит.
                let restitution = -approachSpeed < restingSpeed ? 0 : ballRestitution
                let impulse = -(1 + restitution) * approachSpeed / inverseMassSum

                balls[i].velocity.dx -= normal.dx * impulse * inverseMassI
                balls[i].velocity.dy -= normal.dy * impulse * inverseMassI
                balls[j].velocity.dx += normal.dx * impulse * inverseMassJ
                balls[j].velocity.dy += normal.dy * impulse * inverseMassJ
            }
        }
    }

    /// Не выпускает шар за края экрана и отражает его скорость от стены.
    private func resolveWallCollisions(for ball: inout Ball) {
        let r = ball.radius

        if ball.position.x < r {
            ball.position.x = r
            if ball.velocity.dx < 0 { registerWallImpact(on: &ball, speed: -ball.velocity.dx, angle: .pi) }
            ball.velocity.dx = bounce(ball.velocity.dx, intoWallIfNegative: true)
        } else if ball.position.x > bounds.width - r {
            ball.position.x = bounds.width - r
            if ball.velocity.dx > 0 { registerWallImpact(on: &ball, speed: ball.velocity.dx, angle: 0) }
            ball.velocity.dx = bounce(ball.velocity.dx, intoWallIfNegative: false)
        }

        if ball.position.y < r {
            ball.position.y = r
            if ball.velocity.dy < 0 { registerWallImpact(on: &ball, speed: -ball.velocity.dy, angle: -.pi / 2) }
            ball.velocity.dy = bounce(ball.velocity.dy, intoWallIfNegative: true)
        } else if ball.position.y > bounds.height - r {
            ball.position.y = bounds.height - r
            if ball.velocity.dy > 0 { registerWallImpact(on: &ball, speed: ball.velocity.dy, angle: .pi / 2) }
            ball.velocity.dy = bounce(ball.velocity.dy, intoWallIfNegative: false)
        }

        resolveCornerCollisions(for: &ball)
        resolveObstacleCollision(for: &ball)
    }

    /// Не пускает шар внутрь препятствия со скруглёнными углами и отражает его скорость.
    ///
    /// Скруглённый прямоугольник — это внутренний прямоугольник, «раздутый» на радиус скругления.
    /// Ближайшая к шару точка внутреннего прямоугольника даёт и расстояние, и нормаль удара.
    private func resolveObstacleCollision(for ball: inout Ball) {
        guard let obstacle else { return }
        let cornerRadius = min(obstacle.cornerRadius, obstacle.rect.width / 2, obstacle.rect.height / 2)
        let inner = obstacle.rect.insetBy(dx: cornerRadius, dy: cornerRadius)
        let minDistance = cornerRadius + ball.radius
        let p = ball.position

        var closest = CGPoint(
            x: min(max(p.x, inner.minX), inner.maxX),
            y: min(max(p.y, inner.minY), inner.maxY)
        )
        let dx = p.x - closest.x
        let dy = p.y - closest.y
        let distance = hypot(dx, dy)
        guard distance < minDistance else { return }

        let normal: CGVector
        if distance > 0.0001 {
            normal = CGVector(dx: dx / distance, dy: dy / distance)
        } else {
            // Центр шара глубоко внутри — выталкиваем через ближайшую сторону.
            let exits: [(distance: CGFloat, normal: CGVector, edge: CGPoint)] = [
                (p.x - inner.minX, CGVector(dx: -1, dy: 0), CGPoint(x: inner.minX, y: p.y)),
                (inner.maxX - p.x, CGVector(dx: 1, dy: 0), CGPoint(x: inner.maxX, y: p.y)),
                (p.y - inner.minY, CGVector(dx: 0, dy: -1), CGPoint(x: p.x, y: inner.minY)),
                (inner.maxY - p.y, CGVector(dx: 0, dy: 1), CGPoint(x: p.x, y: inner.maxY))
            ]
            let exit = exits.min { $0.distance < $1.distance } ?? exits[3]
            normal = exit.normal
            closest = exit.edge
        }

        ball.position = CGPoint(
            x: closest.x + normal.dx * minDistance,
            y: closest.y + normal.dy * minDistance
        )

        // Скорость в сторону препятствия (нормаль смотрит от него наружу).
        let intoObstacleSpeed = -(ball.velocity.dx * normal.dx + ball.velocity.dy * normal.dy)
        guard intoObstacleSpeed > 0 else { return }
        registerWallImpact(on: &ball, speed: intoObstacleSpeed, angle: atan2(-normal.dy, -normal.dx))
        let restitution = intoObstacleSpeed < restingSpeed ? 0 : wallRestitution
        ball.velocity.dx += normal.dx * intoObstacleSpeed * (1 + restitution)
        ball.velocity.dy += normal.dy * intoObstacleSpeed * (1 + restitution)
    }

    /// Переносит шары, оказавшиеся внутри препятствия (или вплотную к нему), в свободное место под ним.
    private func moveBallsOutOfObstacle() {
        guard let obstacle, bounds.height > 0 else { return }
        let expanded = obstacle.rect
        for index in balls.indices {
            let r = balls[index].radius
            guard expanded.insetBy(dx: -r, dy: -r).contains(balls[index].position) else { continue }
            let minY = min(expanded.maxY + r, bounds.height - r)
            balls[index].position = CGPoint(
                x: CGFloat.random(in: r...(bounds.width - r)),
                y: CGFloat.random(in: minY...(bounds.height - r))
            )
            balls[index].velocity = .zero
        }
    }

    /// Не пускает шар в скруглённые углы экрана: внутри угла шар должен оставаться
    /// внутри дуги радиуса R, то есть его центр — не дальше (R − r) от центра дуги.
    private func resolveCornerCollisions(for ball: inout Ball) {
        let r = ball.radius
        let w = bounds.width
        let h = bounds.height
        let p = ball.position

        // Ближайший к шару угол экрана (по половинам экрана) — радиус скругления и центр его дуги.
        // Считаем без массивов: функция вызывается для каждого шара много раз за кадр.
        let isLeft = p.x < w / 2
        let isTop = p.y < h / 2
        let cornerRadius = isTop
            ? (isLeft ? cornerRadii.topLeading : cornerRadii.topTrailing)
            : (isLeft ? cornerRadii.bottomLeading : cornerRadii.bottomTrailing)
        let cornerCenter = CGPoint(
            x: isLeft ? cornerRadius : w - cornerRadius,
            y: isTop ? cornerRadius : h - cornerRadius
        )

        // Скругление действует, только когда центр шара попал в угловой квадрат.
        let isInCornerX = isLeft ? p.x < cornerCenter.x : p.x > cornerCenter.x
        let isInCornerY = isTop ? p.y < cornerCenter.y : p.y > cornerCenter.y
        guard isInCornerX, isInCornerY else { return }
        // Если шар больше скругления, его и так удерживают прямые стены.
        let limit = cornerRadius - r
        guard limit > 0 else { return }

        let dx = p.x - cornerCenter.x
        let dy = p.y - cornerCenter.y
        let distance = hypot(dx, dy)
        guard distance > limit, distance > 0.0001 else { return }

        // Возвращаем шар на дугу и отражаем скорость по нормали к ней (нормаль смотрит наружу).
        let normal = CGVector(dx: dx / distance, dy: dy / distance)
        ball.position = CGPoint(
            x: cornerCenter.x + normal.dx * limit,
            y: cornerCenter.y + normal.dy * limit
        )
        let outwardSpeed = ball.velocity.dx * normal.dx + ball.velocity.dy * normal.dy
        guard outwardSpeed > 0 else { return }
        registerWallImpact(on: &ball, speed: outwardSpeed, angle: atan2(normal.dy, normal.dx))
        let restitution = outwardSpeed < restingSpeed ? 0 : wallRestitution
        ball.velocity.dx -= normal.dx * outwardSpeed * (1 + restitution)
        ball.velocity.dy -= normal.dy * outwardSpeed * (1 + restitution)
    }

    /// Удар о стену или скругление экрана: помимо реакции шара запоминаем силу удара для тактильного отклика.
    private func registerWallImpact(on ball: inout Ball, speed: CGFloat, angle: CGFloat) {
        strongestWallImpactSpeed = max(strongestWallImpactSpeed, speed)
        registerImpact(on: &ball, speed: speed, angle: angle)
    }

    /// Реакция шара на удар: вспышка и сплющивание, тем сильнее, чем сильнее удар.
    /// Слабые касания (шар лежит в куче) ничего не вызывают, иначе куча «дышала» и мерцала бы.
    private func registerImpact(on ball: inout Ball, speed: CGFloat, angle: CGFloat) {
        if speed >= flashThresholdSpeed {
            let brightness = Double(min(1, (speed - flashThresholdSpeed) / (fullFlashImpactSpeed - flashThresholdSpeed)))
            ball.flash = max(ball.flash, brightness)
        }

        guard speed >= restingSpeed else { return }
        let amount = min(maxSquash, maxSquash * speed / fullSquashImpactSpeed)
        // Новый удар перекрывает старый, только если он сильнее текущей деформации.
        if amount > ball.squash {
            ball.squash = amount
            ball.squashAngle = angle
        }
    }

    /// Отражённая составляющая скорости после удара о стену; слабые удары гасятся полностью.
    /// Если шар уже движется от стены (его прижал сосед), скорость не трогаем, чтобы не развернуть его обратно.
    private func bounce(_ component: CGFloat, intoWallIfNegative: Bool) -> CGFloat {
        let movingIntoWall = intoWallIfNegative ? component < 0 : component > 0
        guard movingIntoWall else { return component }
        return abs(component) < restingSpeed ? 0 : -component * wallRestitution
    }

    // MARK: - Начальная раскладка

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
