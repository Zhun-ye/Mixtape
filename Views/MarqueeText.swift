import SwiftUI

// MARK: - MarqueeText

/// A scrolling text view that animates when text overflows, similar to Apple Music.
struct MarqueeText: View {
    let text: String
    var startDelay: Double = 2.0

    @State private var animate = false
    @State private var textWidth: CGFloat = 0
    @State private var textHeight: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var needsScrolling: Bool {
        textWidth > containerWidth && containerWidth > 0
    }

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                containerWidth = newWidth
            }
            .overlay(alignment: .leading) {
                // Hidden text to measure size
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { size in
                        let wasScrolling = needsScrolling
                        textWidth = size.width
                        textHeight = size.height
                        if needsScrolling && !wasScrolling {
                            animate = false
                            DispatchQueue.main.async {
                                animate = true
                            }
                        }
                    }
            }
            .overlay(alignment: .leading) {
                if containerWidth > 0 && textWidth > 0 {
                    if needsScrolling {
                        marqueeContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(animate ? 1 : 0)

                        // Static text shown before animation starts
                        if !animate {
                            Text(text)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    } else {
                        Text(text)
                            .lineLimit(1)
                    }
                }
            }
            .clipped()
            .onAppear {
                if needsScrolling {
                    animate = true
                }
            }
            .onDisappear {
                animate = false
            }
            .onChange(of: text) {
                animate = false
                DispatchQueue.main.async {
                    if needsScrolling {
                        animate = true
                    }
                }
            }
    }

    private var marqueeContent: some View {
        let animation = Animation
            .linear(duration: Double(textWidth) / 30)
            .delay(startDelay)
            .repeatForever(autoreverses: false)
        let nullAnimation = Animation.linear(duration: 0)
        let spacing = textHeight * 2

        return HStack(spacing: spacing) {
            Text(text)
                .lineLimit(1)
                .fixedSize()
            Text(text)
                .lineLimit(1)
                .fixedSize()
        }
        .offset(x: animate ? -textWidth - spacing : 0)
        .animation(animate ? animation : nullAnimation, value: animate)
    }

}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        MarqueeText(text: "Short text")
            .font(.system(size: 14))
            .frame(width: 200, height: 20)
            .border(.red)

        MarqueeText(text: "This is a very long text that should scroll because it overflows")
            .font(.system(size: 14))
            .frame(width: 200, height: 20)
            .border(.red)
    }
    .padding()
}
