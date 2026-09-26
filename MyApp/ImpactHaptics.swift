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
    /// Совпадает с порогом вспышек: при обычном наклоне телефона удары в основном 150–500 pt/с.
    let thresholdSpeed: CGFloat = 150
    /// Скорость удара, при которой отклик максимальный.
    let fullIntensitySpeed: CGFloat = 900
    /// Минимальный интервал между откликами в секундах (не больше 4 раз в секунду).
    let minimumInterval: TimeInterval = 0.25

    private var lastFeedbackDate: Date?

    #if os(iOS)
    /// `.medium` отчётливо ощущается даже на слабых ударах (у `.soft` отклик почти незаметен).
    private let generator = UIImpactFeedbackGenerator(style: .medium)
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

        // Слабые удары дают лёгкий, но ощутимый отклик, сильные — полный.
        let progress = min(1, (speed - thresholdSpeed) / (fullIntensitySpeed - thresholdSpeed))
        let intensity = 0.55 + 0.45 * progress
        #if os(iOS)
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
        #endif
    }
}
