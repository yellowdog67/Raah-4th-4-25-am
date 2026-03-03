import SwiftUI

// MARK: - Main Orb Router

struct OrbView: View {
    let style: OrbStyle
    let accentTheme: AccentTheme
    let voiceState: VoiceState
    let heartRate: Double?
    let size: CGFloat
    
    var body: some View {
        switch style {
        case .fluid:
            FluidOrbView(accentTheme: accentTheme, voiceState: voiceState, heartRate: heartRate, size: size)
        case .crystal:
            CrystalOrbView(accentTheme: accentTheme, voiceState: voiceState, heartRate: heartRate, size: size)
        case .pulseRing:
            PulseRingOrbView(accentTheme: accentTheme, voiceState: voiceState, heartRate: heartRate, size: size)
        }
    }
}

// MARK: - 1. Fluid Orb

struct FluidOrbView: View {
    let accentTheme: AccentTheme
    let voiceState: VoiceState
    let heartRate: Double?
    let size: CGFloat
    
    @State private var morphPhase: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var breatheScale: CGFloat = 1.0
    @State private var glowIntensity: CGFloat = 0.3
    
    private var pulseInterval: Double {
        guard let hr = heartRate, hr > 0 else { return 3.0 }
        return 60.0 / hr
    }
    
    private let timeOfDay = TimeOfDayPalette()
    
    var body: some View {
        ZStack {
            // Outer glow (green when listening = mic is taking input)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (voiceState == .listening ? Color.green : accentTheme.color).opacity(glowIntensity),
                            (voiceState == .listening ? Color.mint : accentTheme.color).opacity(glowIntensity * 0.5),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.3,
                        endRadius: size * 0.8
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .blur(radius: 30)
            
            // Main orb body
            ZStack {
                // Base gradient sphere
                Circle()
                    .fill(
                        RadialGradient(
                            colors: orbColors,
                            center: UnitPoint(x: 0.3 + sin(morphPhase) * 0.15, y: 0.3 + cos(morphPhase) * 0.15),
                            startRadius: 0,
                            endRadius: size * 0.55
                        )
                    )
                
                // Secondary morphing gradient
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentTheme.color.opacity(0.6),
                                accentTheme.gradient[1].opacity(0.3),
                                Color.clear
                            ],
                            center: UnitPoint(
                                x: 0.6 + cos(morphPhase * 1.3) * 0.2,
                                y: 0.5 + sin(morphPhase * 0.8) * 0.2
                            ),
                            startRadius: 0,
                            endRadius: size * 0.4
                        )
                    )
                    .blendMode(.plusLighter)
                
                // Glass highlight
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(timeOfDay.isDaytime ? 0.5 : 0.25),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: size * 0.5, height: size * 0.3)
                    .offset(x: -size * 0.05, y: -size * 0.12)
                    .rotationEffect(.degrees(-15))
                
                // Inner refraction ring
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: accentTheme.gradient + [accentTheme.gradient[0]],
                            center: .center,
                            startAngle: .degrees(rotationAngle),
                            endAngle: .degrees(rotationAngle + 360)
                        ),
                        lineWidth: 1.5
                    )
                    .opacity(0.4)
                    .padding(2)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .scaleEffect(breatheScale)
            .shadow(color: accentTheme.color.opacity(0.3), radius: 25, x: 0, y: 0)
            
            // Voice state particles
            if voiceState == .listening {
                ListeningParticles(color: accentTheme.color, size: size)
            }
            
            if voiceState == .speaking {
                SpeakingRipples(color: accentTheme.color, size: size)
            }
        }
        .onAppear { startAnimations() }
        .onChange(of: voiceState) { _, newState in
            updateForVoiceState(newState)
        }
    }
    
    private var orbColors: [Color] {
        if voiceState == .listening {
            return [
                Color.green.opacity(0.95),
                Color.mint.opacity(0.8),
                Color.green.opacity(0.5),
                Color.mint.opacity(0.3)
            ]
        }
        let base = timeOfDay.orbBase
        return [
            accentTheme.color.opacity(0.9),
            accentTheme.gradient[1].opacity(0.7),
            base[0].opacity(0.5),
            base[1].opacity(0.3)
        ]
    }
    
    private func startAnimations() {
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            morphPhase = .pi * 2
        }
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
        withAnimation(.easeInOut(duration: pulseInterval).repeatForever(autoreverses: true)) {
            breatheScale = 1.06
        }
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            glowIntensity = 0.5
        }
    }
    
    private func updateForVoiceState(_ state: VoiceState) {
        withAnimation(RAAHTheme.Motion.snappy) {
            switch state {
            case .idle:
                breatheScale = 1.0
                glowIntensity = 0.3
            case .listening:
                breatheScale = 1.1
                glowIntensity = 0.6
            case .thinking:
                breatheScale = 0.95
                glowIntensity = 0.4
            case .speaking:
                breatheScale = 1.08
                glowIntensity = 0.7
            case .reconnecting:
                breatheScale = 0.9
                glowIntensity = 0.35
            case .paused:
                breatheScale = 0.95
                glowIntensity = 0.15
            case .error:
                breatheScale = 0.9
                glowIntensity = 0.2
            }
        }
    }
}

// MARK: - 2. Crystal Orb

struct CrystalOrbView: View {
    let accentTheme: AccentTheme
    let voiceState: VoiceState
    let heartRate: Double?
    let size: CGFloat
    
    @State private var rotation: Double = 0
    @State private var breatheScale: CGFloat = 1.0
    
    private var pulseInterval: Double {
        guard let hr = heartRate, hr > 0 else { return 3.0 }
        return 60.0 / hr
    }
    
    private var activeColor: Color {
        voiceState == .listening ? .green : accentTheme.color
    }
    
    var body: some View {
        ZStack {
            // Glow (green when listening = mic on)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [activeColor.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: size * 0.2,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)
                .blur(radius: 25)
            
            // Faceted crystal layers
            ForEach(0..<6) { i in
                RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                activeColor.opacity(0.15 - Double(i) * 0.02),
                                (voiceState == .listening ? Color.mint : accentTheme.gradient[1]).opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * (0.9 - CGFloat(i) * 0.08), height: size * (0.9 - CGFloat(i) * 0.08))
                    .rotationEffect(.degrees(rotation + Double(i) * 15))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
                            .strokeBorder(
                                activeColor.opacity(0.2 - Double(i) * 0.025),
                                lineWidth: 0.5
                            )
                            .rotationEffect(.degrees(rotation + Double(i) * 15))
                    }
            }
            
            // Center crystal
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            activeColor.opacity(0.5),
                            (voiceState == .listening ? Color.mint : accentTheme.gradient[2]).opacity(0.3)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: size * 0.25
                    )
                )
                .frame(width: size * 0.5, height: size * 0.5)
                .shadow(color: activeColor.opacity(0.4), radius: 15)
        }
        .scaleEffect(breatheScale)
        .onAppear {
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: pulseInterval).repeatForever(autoreverses: true)) {
                breatheScale = 1.04
            }
        }
    }
}

// MARK: - 3. Pulse Ring Orb

struct PulseRingOrbView: View {
    let accentTheme: AccentTheme
    let voiceState: VoiceState
    let heartRate: Double?
    let size: CGFloat
    
    @State private var ringScales: [CGFloat] = [1.0, 1.0, 1.0, 1.0]
    @State private var ringOpacities: [Double] = [0.6, 0.45, 0.3, 0.15]
    
    private var pulseInterval: Double {
        guard let hr = heartRate, hr > 0 else { return 3.0 }
        return 60.0 / hr
    }
    
    private var activeColor: Color {
        voiceState == .listening ? .green : accentTheme.color
    }
    
    var body: some View {
        ZStack {
            ForEach(0..<4) { i in
                Circle()
                    .strokeBorder(
                        activeColor.opacity(ringOpacities[i]),
                        lineWidth: i == 0 ? 3 : 1.5
                    )
                    .frame(
                        width: size * (0.3 + CGFloat(i) * 0.2) * ringScales[i],
                        height: size * (0.3 + CGFloat(i) * 0.2) * ringScales[i]
                    )
            }
            
            // Center dot (green when listening = mic on)
            Circle()
                .fill(activeColor)
                .frame(width: 12, height: 12)
                .shadow(color: activeColor.opacity(0.6), radius: 10)
        }
        .onAppear {
            animateRings()
        }
    }
    
    private func animateRings() {
        for i in 0..<4 {
            let delay = Double(i) * 0.15
            withAnimation(
                .easeInOut(duration: pulseInterval)
                .repeatForever(autoreverses: true)
                .delay(delay)
            ) {
                ringScales[i] = 1.15
                ringOpacities[i] = ringOpacities[i] * 0.5
            }
        }
    }
}

// MARK: - Listening Particles

struct ListeningParticles: View {
    let color: Color
    let size: CGFloat
    
    @State private var particles: [(offset: CGSize, opacity: Double)] = []
    @State private var animating = false
    
    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Circle()
                    .fill(color.opacity(animating ? 0.0 : 0.6))
                    .frame(width: 4, height: 4)
                    .offset(
                        x: animating ? CGFloat.random(in: -size * 0.6...size * 0.6) : 0,
                        y: animating ? CGFloat.random(in: -size * 0.6...size * 0.6) : 0
                    )
                    .scaleEffect(animating ? 0.3 : 1.0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
    }
}

// MARK: - Speaking Ripples

struct SpeakingRipples: View {
    let color: Color
    let size: CGFloat
    
    @State private var ripple1: CGFloat = 1.0
    @State private var ripple2: CGFloat = 1.0
    @State private var ripple3: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(0.3 / Double(ripple1)), lineWidth: 1)
                .frame(width: size * ripple1, height: size * ripple1)
            
            Circle()
                .strokeBorder(color.opacity(0.3 / Double(ripple2)), lineWidth: 1)
                .frame(width: size * ripple2, height: size * ripple2)
            
            Circle()
                .strokeBorder(color.opacity(0.3 / Double(ripple3)), lineWidth: 1)
                .frame(width: size * ripple3, height: size * ripple3)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                ripple1 = 1.8
            }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(0.6)) {
                ripple2 = 1.8
            }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(1.2)) {
                ripple3 = 1.8
            }
        }
    }
}
