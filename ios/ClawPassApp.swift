import SwiftUI
import UIKit

@main
struct ClawPassApp: App {
    @ObservedObject private var theme = ThemeStore.shared

    init() { BrandAssets.warm() }

    var body: some Scene {
        WindowGroup {
            // Rebuilding on a theme change makes every screen re-read the palette.
            ContentView()
                .themeFont()
                .id(theme.current.id)
        }
    }
}

/// The brand moment on the unlock screen: the shackle drops, the lock clunks shut with a tap, a glint crosses
/// the steel, then the name builds beneath it. `embedded` sits it above the password box on the theme colours.
struct SplashView: View {
    var embedded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var night: Bool { embedded || colorScheme == .dark }
    @State private var markIn = false
    @State private var shackleDown = false
    @State private var clunk = false
    @State private var flash = false
    @State private var ringPhase = 0
    @State private var shake = 0
    @State private var lettersIn = false
    @State private var ruleIn = false
    @State private var byIn = false

    private let letters = Array("VAULTINATOR")
    private let markHeight: CGFloat = 245
    private let markWidth: CGFloat = 124
    private var ink: Color { embedded ? Palette.textPrimary : night ? Color(red: 0.93, green: 0.95, blue: 0.97) : Color(red: 0.07, green: 0.16, blue: 0.36) }
    private var slate: Color { embedded ? Palette.textSecondary : night ? Color(red: 0.60, green: 0.63, blue: 0.68) : Color(red: 0.26, green: 0.27, blue: 0.29) }

    var body: some View {
        ZStack {
            if !embedded { (night ? Color.black : Color.white).ignoresSafeArea() }
            if night {
                RadialGradient(colors: [Color(red: 0.38, green: 0.49, blue: 0.75).opacity(0.2), .clear],
                               center: .center, startRadius: 0, endRadius: 260)
                    .frame(width: embedded ? 320 : 520, height: embedded ? 320 : 520)
                    .offset(y: -70)
                    .opacity(markIn ? 1 : 0)
            }
            VStack(spacing: 0) {
                lockMark
                    .padding(.bottom, 30)
                wordmark
                Capsule()
                    .fill(LinearGradient(colors: [Color.gray.opacity(0), Color(white: night ? 0.6 : 0.5), Color.gray.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 190, height: 2)
                    .scaleEffect(x: ruleIn ? 1 : 0, y: 1)
                    .opacity(ruleIn ? 1 : 0)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                Text("SECURED BY VAULTINATOR")
                    .font(BrandAssets.font(13))
                    .tracking(3)
                    .foregroundColor(slate)
                    .opacity(byIn ? 1 : 0)
                    .offset(y: byIn ? 0 : 6)
            }
        }
        .offset(x: shake == 0 ? 0 : (shake % 2 == 1 ? 5 : -5), y: shake == 0 ? 0 : (shake % 2 == 1 ? 2 : -2))
        .scaleEffect(embedded ? 0.78 : 1)
        .accessibilityHidden(true)
        .onAppear { BrandAssets.playLock(); run() }
    }

    private var lockMark: some View {
        let image = Image(night ? "LayerMarkDark" : "LayerMark").resizable().scaledToFit()
        return ZStack {
            // Body: lower 64% of the artwork.
            ZStack { image }
                .frame(width: markWidth, height: markHeight)
                .mask(alignment: .bottom) { Rectangle().frame(height: markHeight * 0.59) }
            // Shackle: upper 36%, clipped in place while the artwork inside it drops.
            ZStack { image }
                .frame(width: markWidth, height: markHeight)
                .mask(alignment: .top) { Rectangle().frame(height: markHeight * 0.61).offset(y: -markHeight * 0.2).frame(height: markHeight * 0.41, alignment: .top) }
                .offset(y: shackleDown ? 0 : -markHeight * 0.16)
            // Impact flash: white-hot for an instant, only where the steel is.
            Rectangle()
                .fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.82, blue: 0.55), .clear],
                                     center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: markHeight * 0.55))
                .opacity(flash ? 0.85 : 0)
                .frame(width: markWidth, height: markHeight)
                .mask { Image("LayerMarkDark").resizable().scaledToFit().frame(width: markWidth, height: markHeight) }
        }
        .frame(width: markWidth, height: markHeight)
        .background(
            Circle().stroke(Color.white.opacity(0.7), lineWidth: 3)
                .frame(width: 90, height: 90)
                .scaleEffect(ringPhase == 2 ? 5.5 : 0.3)
                .opacity(ringPhase == 1 ? 0.8 : 0)
                .offset(y: -markHeight * 0.08)
        )
        .scaleEffect(clunk ? 0.965 : (markIn ? 1 : 0.94))
        .opacity(markIn ? 1 : 0)
    }

    private var wordmark: some View {
        HStack(spacing: 4) {
            ForEach(letters.indices, id: \.self) { i in
                Text(String(letters[i]))
                    .font(BrandAssets.font(36))
                    .foregroundColor(ink)
                    .offset(y: lettersIn ? 0 : 52)
                    .opacity(lettersIn ? 1 : 0)
                    .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55).delay(Double(i) * 0.07), value: lettersIn)
            }
        }
        .frame(height: 56)
        .clipped()
    }

    private func run() {
        if reduceMotion {
            markIn = true; shackleDown = true; lettersIn = true; ruleIn = true; byIn = true
            return
        }
        withAnimation(.easeOut(duration: 0.5)) { markIn = true }
        // The shackle hovers open, then slams shut at 1.05s, in step with the vault sound.
        after(0.72) { withAnimation(.timingCurve(0.6, 0, 1, 0.5, duration: 0.33)) { shackleDown = true } }
        after(1.05) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            withAnimation(.easeOut(duration: 0.05)) { clunk = true; flash = true }
            after(0.05) { withAnimation(.easeOut(duration: 0.3)) { clunk = false; flash = false } }
            ringPhase = 1
            DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.9)) { ringPhase = 2 } }
            for k in 1...6 { after(Double(k) * 0.045) { shake = k < 6 ? k : 0 } }
        }
        after(1.42) { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6) }
        after(1.62) { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7) }
        after(1.35) { lettersIn = true }
        after(1.85) { withAnimation(.easeOut(duration: 0.6)) { ruleIn = true } }
        after(2.0) { withAnimation(.easeOut(duration: 0.6)) { byIn = true } }
        after(1.95) { UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.8) }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
