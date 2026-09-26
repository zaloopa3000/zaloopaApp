import CoreGraphics
#if os(iOS)
import CoreMotion
#endif

/// Читает наклон телефона и переводит его в «гравитацию» для шаров.
///
/// Данные датчиков не приходят через обработчик, а считываются раз в кадр —
/// Apple рекомендует такой подход для игр: нужен только самый свежий сэмпл.
final class MotionManager {
    #if os(iOS)
    private let motionManager = CMMotionManager()
    #endif

    /// Есть ли на устройстве датчики движения (в симуляторе и на Mac — нет).
    var isAvailable: Bool {
        #if os(iOS)
        motionManager.isDeviceMotionAvailable
        #else
        false
        #endif
    }

    func start() {
        #if os(iOS)
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates()
        #endif
    }

    func stop() {
        #if os(iOS)
        motionManager.stopDeviceMotionUpdates()
        #endif
    }

    /// Проекция земной гравитации на плоскость экрана в экранных координатах (y смотрит вниз).
    /// Длина вектора 0…1: 0 — телефон лежит горизонтально, 1 — стоит вертикально.
    /// `nil`, пока датчики недоступны или ещё не прислали первый сэмпл.
    var screenGravity: CGVector? {
        #if os(iOS)
        guard let gravity = motionManager.deviceMotion?.gravity else { return nil }
        // У датчика ось y направлена к верху телефона, а на экране — вниз, поэтому меняем знак.
        return CGVector(dx: gravity.x, dy: -gravity.y)
        #else
        nil
        #endif
    }
}
