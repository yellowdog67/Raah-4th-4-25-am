import SwiftUI

struct WaveformView: View {
    let isActive: Bool
    let color: Color
    let barCount: Int
    
    @State private var heights: [CGFloat]
    
    init(isActive: Bool, color: Color, barCount: Int = 5) {
        self.isActive = isActive
        self.color = color
        self.barCount = barCount
        self._heights = State(initialValue: Array(repeating: 0.3, count: barCount))
    }
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3, height: isActive ? heights[i] * 24 : 4)
                    .animation(
                        isActive
                            ? .easeInOut(duration: Double.random(in: 0.3...0.6))
                              .repeatForever(autoreverses: true)
                              .delay(Double(i) * 0.1)
                            : .easeOut(duration: 0.3),
                        value: isActive
                    )
            }
        }
        .onChange(of: isActive) { _, active in
            if active { randomizeHeights() }
        }
        .onAppear {
            if isActive { randomizeHeights() }
        }
    }
    
    private func randomizeHeights() {
        heights = (0..<barCount).map { _ in CGFloat.random(in: 0.3...1.0) }
        
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { timer in
            if !isActive { timer.invalidate(); return }
            withAnimation {
                heights = (0..<barCount).map { _ in CGFloat.random(in: 0.3...1.0) }
            }
        }
    }
}

// MARK: - Circular Waveform (around orb)

struct CircularWaveform: View {
    let isActive: Bool
    let color: Color
    let radius: CGFloat
    
    @State private var amplitudes: [CGFloat] = Array(repeating: 0, count: 36)
    
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            
            for i in 0..<36 {
                let angle = Double(i) * 10 * .pi / 180
                let amp = isActive ? amplitudes[i] * 15 : 2
                let innerR = radius - amp / 2
                let outerR = radius + amp / 2
                
                let startPoint = CGPoint(
                    x: center.x + innerR * cos(angle),
                    y: center.y + innerR * sin(angle)
                )
                let endPoint = CGPoint(
                    x: center.x + outerR * cos(angle),
                    y: center.y + outerR * sin(angle)
                )
                
                var path = Path()
                path.move(to: startPoint)
                path.addLine(to: endPoint)
                
                context.stroke(
                    path,
                    with: .color(color.opacity(0.5)),
                    lineWidth: 2
                )
            }
        }
        .frame(width: radius * 2.4, height: radius * 2.4)
        .onChange(of: isActive) { _, active in
            if active { startWaveAnimation() }
        }
    }
    
    private func startWaveAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
            if !isActive { timer.invalidate(); return }
            withAnimation(.easeInOut(duration: 0.15)) {
                amplitudes = (0..<36).map { _ in CGFloat.random(in: 0.1...1.0) }
            }
        }
    }
}
