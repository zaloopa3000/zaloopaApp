import Foundation
import ImageIO

/// Анимированная гифка, заранее разложенная на кадры.
nonisolated struct AnimatedGIF: Sendable {
    let frames: [CGImage]
    /// Длительность показа каждого кадра в секундах.
    let frameDurations: [Double]
    let totalDuration: Double

    /// Кадр, который нужно показать в момент `time` (анимация зациклена).
    func frame(at time: TimeInterval) -> CGImage {
        guard frames.count > 1, totalDuration > 0 else { return frames[0] }
        var remaining = time.truncatingRemainder(dividingBy: totalDuration)
        for (index, duration) in frameDurations.enumerated() {
            if remaining < duration { return frames[index] }
            remaining -= duration
        }
        return frames[frames.count - 1]
    }
}

nonisolated enum GiphyError: LocalizedError {
    case badStatus(Int)
    case noImage
    case undecodableGIF

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): "GIPHY вернул ошибку \(code)"
        case .noImage: "В ответе GIPHY нет гифки"
        case .undecodableGIF: "Не удалось прочитать гифку"
        }
    }
}

/// Загрузка случайной гифки через GIPHY API.
nonisolated enum GiphyClient {
    /// Ключ GIPHY API. Он зашит в приложение, поэтому его можно извлечь из сборки:
    /// для публикации лучше получать его с собственного сервера.
    private static let apiKey = "YUC2xffXdOzJP7JRlLH84mNu1Gt9Zmx7"
    /// Возрастной рейтинг гифок: «g» — подходит для всех.
    private static let rating = "g"
    /// Максимальный размер кадра в пикселях: хватает для блока на экране и экономит память.
    private static let maxPixelSize = 720

    /// Загружает случайную гифку и раскладывает её на кадры. Работает вне главного потока.
    @concurrent
    static func fetchRandomGIF() async throws -> AnimatedGIF {
        var components = URLComponents(string: "https://api.giphy.com/v1/gifs/random")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "rating", value: rating)
        ]
        guard let requestURL = components?.url else { throw GiphyError.noImage }

        let (json, response) = try await URLSession.shared.data(from: requestURL)
        try validate(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let images = try decoder.decode(RandomResponse.self, from: json).data.images
        // «downsized» — облегчённая версия до 2 МБ: хорошее качество без долгой загрузки.
        guard let gifURL = images.downsized?.url ?? images.fixedHeight?.url ?? images.original?.url else {
            throw GiphyError.noImage
        }

        let (gifData, gifResponse) = try await URLSession.shared.data(from: gifURL)
        try validate(gifResponse)
        try Task.checkCancellation()
        return try decodeGIF(gifData)
    }

    private static func validate(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GiphyError.badStatus(http.statusCode)
        }
    }

    /// Раскладывает GIF на уменьшенные кадры и читает длительность каждого кадра.
    private static func decodeGIF(_ data: Data) throws -> AnimatedGIF {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw GiphyError.undecodableGIF
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        var frames: [CGImage] = []
        var durations: [Double] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary) else {
                continue
            }
            frames.append(frame)
            durations.append(frameDuration(in: source, at: index))
        }
        guard !frames.isEmpty else { throw GiphyError.undecodableGIF }
        return AnimatedGIF(frames: frames, frameDurations: durations, totalDuration: durations.reduce(0, +))
    }

    /// Длительность кадра из метаданных GIF. Слишком короткие задержки браузеры показывают
    /// как 0.1 с — делаем так же, иначе некоторые гифки проигрывались бы слишком быстро.
    private static func frameDuration(in source: CGImageSource, at index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }

    // MARK: - Ответ GIPHY

    private struct RandomResponse: Decodable {
        let data: GIFObject
    }

    private struct GIFObject: Decodable {
        let images: Images
    }

    private struct Images: Decodable {
        let downsized: Rendition?
        let fixedHeight: Rendition?
        let original: Rendition?
    }

    private struct Rendition: Decodable {
        let url: URL
    }
}
