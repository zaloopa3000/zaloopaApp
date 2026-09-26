import Foundation
#if os(iOS)
import UIKit
#endif

/// Мягкий тактильный отклик при сильных ударах шаров о стены.
///
/// Отклик срабатывает не чаще нескольких раз в секунду: при тряске телефона шары бьются
/// о стены почти непрерывно, и без ограничения вибрация сливалась бы в сплошное «гудение».
final class ImpactHaptics {
    /// Скорость удара о стену (pt/с), начиная с которой чувствуется отклик.
    let thresholdSpeed: CGFloat = 500
    /// Скорость удара, при которой отклик максимальный.
    let fullIntensitySpeed: CGFloat = 1500
    /// Минимальный интервал между откликами в секундах (не больше 4 раз в секунду).
    let minimumInterval: TimeInterval = 0.25

    private var lastFeedbackDate: Date?

    #if os(iOS)
    private let generator = UIImpactFeedbackGenerator(style: .soft)
    #endif

    /// Держит тактильный движок «разогретым», чтобы отклик не запаздывал.
    func prepare() {
        #if os(iOS)
        generator.prepare()
        #endif
    }

    /// Вызывается раз в кадр с силой самого сильного удара о стену за этот кадр.
    func handleWallImpact(speed: CGFloat, at date: Date) {
        guard speed >= thresholdSpeed else { return }
        if let lastFeedbackDate, date.timeIntervalSince(lastFeedbackDate) < minimumInterval { return }
        lastFeedbackDate = date

        // Слабые удары дают лёгкий отклик, сильные — отчётливый, но всё равно мягкий.
        let progress = min(1, (speed - thresholdSpeed) / (fullIntensitySpeed - thresholdSpeed))
        let intensity = 0.35 + 0.65 * progress
        #if os(iOS)
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
        #endif
    }
}
