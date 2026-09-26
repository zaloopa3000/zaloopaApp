import SwiftUI

/// Состояние загрузки гифки для карточки.
@Observable
final class GIFLoader {
    private(set) var gif: AnimatedGIF?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Загружает новую случайную гифку. Пока идёт загрузка, старая гифка остаётся на экране.
    func loadRandom() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            gif = try await GiphyClient.fetchRandomGIF()
        } catch is CancellationError {
            // Экран закрыли во время загрузки — показывать ошибку не нужно.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Блок со случайной гифкой из GIPHY и кнопкой «новая гифка» в правом верхнем углу.
struct GIFCardView: View {
    /// Радиус скругления блока; физика шаров использует тот же радиус.
    static let cornerRadius: CGFloat = 24

    @State private var loader = GIFLoader()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.06))
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                refreshButton
                    .padding(10)
            }
            .task { await loader.loadRandom() }
    }

    @ViewBuilder
    private var content: some View {
        if let gif = loader.gif {
            AnimatedGIFView(gif: gif)
        } else if let errorMessage = loader.errorMessage {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                Text(errorMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding()
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    /// Иконка 24×24 на полупрозрачной подложке, чтобы её было видно на любой гифке.
    private var refreshButton: some View {
        Button {
            Task { await loader.loadRandom() }
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.45))
                if loader.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 24, height: 24)
            // Сама иконка 24×24, но область нажатия больше — в неё проще попасть пальцем.
            .padding(10)
            .contentShape(.rect)
            .padding(-10)
        }
        .buttonStyle(.plain)
        .disabled(loader.isLoading)
        .accessibilityLabel("Загрузить новую гифку")
    }
}

/// Проигрывает заранее разложенную на кадры гифку, заполняя всю доступную область.
struct AnimatedGIFView: View {
    let gif: AnimatedGIF

    var body: some View {
        // Прозрачная подложка занимает ровно предложенный размер, а гифка заполняет её поверх.
        // Если применить scaledToFill к самой картинке без подложки, она раздувает рамку блока
        // до своих пропорций и вылезает за его пределы.
        Color.clear
            .overlay {
                TimelineView(.animation) { timeline in
                    Image(decorative: gif.frame(at: timeline.date.timeIntervalSinceReferenceDate), scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
    }
}

#Preview {
    GIFCardView()
        .frame(height: 180)
        .padding()
        .background(.black)
}
