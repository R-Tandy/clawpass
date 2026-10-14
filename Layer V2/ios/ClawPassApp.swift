import SwiftUI
import UIKit

@main
struct ClawPassApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
            }
        }
    }
}

/// Launch moment: the shackle drops, the lock clunks shut with a tap, a glint crosses the steel,
/// then the name builds beneath it.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var night: Bool { colorScheme == .dark }
    @State private var markIn = false
    @State private var shackleDown = false
    @State private var clunk = false
    @State private var glint = false
    @State private var lettersIn = false
    @State private var ruleIn = false
    @State private var byIn = false

    private let letters = Array("LAYER")
    private let markHeight: CGFloat = 245
    private let markWidth: CGFloat = 124
    private var ink: Color { night ? Color(red: 0.93, green: 0.95, blue: 0.97) : Color(red: 0.07, green: 0.16, blue: 0.36) }
    private var slate: Color { night ? Color(red: 0.60, green: 0.63, blue: 0.68) : Color(red: 0.26, green: 0.27, blue: 0.29) }

    var body: some View {
        ZStack {
            (night ? Color.black : Color.white).ignoresSafeArea()
            if night {
                RadialGradient(colors: [Color(red: 0.38, green: 0.49, blue: 0.75).opacity(0.2), .clear],
                               center: .center, startRadius: 0, endRadius: 260)
                    .frame(width: 520, height: 520)
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
                Text("by Tandy Pro Services")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(slate)
                    .opacity(byIn ? 1 : 0)
                    .offset(y: byIn ? 0 : 6)
            }
        }
        .accessibilityHidden(true)
        .onAppear(perform: run)
    }

    private var lockMark: some View {
        let image = Image(night ? "LayerMarkDark" : "LayerMark").resizable().scaledToFit()
        return ZStack {
            // Body: lower 64% of the artwork.
            ZStack { image }
                .frame(width: markWidth, height: markHeight)
                .mask(alignment: .bottom) { Rectangle().frame(height: markHeight * 0.59) }
            // Shackle: upper 36%, clipped in place while the artwork inside it drops.
            ZStack { image.offset(y: shackleDown ? 0 : -markHeight * 0.05) }
                .frame(width: markWidth, height: markHeight)
                .mask(alignment: .top) { Rectangle().frame(height: markHeight * 0.41) }
            // Glint across the steel.
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.95), .white.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: markWidth * 0.46, height: markHeight * 1.2)
                .rotationEffect(.degrees(12))
                .offset(x: glint ? markWidth * 0.9 : -markWidth * 0.9)
                .blendMode(.softLight)
                .frame(width: markWidth, height: markHeight)
                // The glint only shows where the lock is, never on the background.
                .mask { Image("LayerMarkDark").resizable().scaledToFit().frame(width: markWidth, height: markHeight) }
        }
        .frame(width: markWidth, height: markHeight)
        .clipped()
        .scaleEffect(clunk ? 0.982 : (markIn ? 1 : 0.94))
        .opacity(markIn ? 1 : 0)
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            ForEach(letters.indices, id: \.self) { i in
                Text(String(letters[i]))
                    .font(.system(size: 46, weight: .heavy))
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
        after(0.45) { withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.55)) { shackleDown = true } }
        after(0.95) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            withAnimation(.easeOut(duration: 0.09)) { clunk = true }
            after(0.09) { withAnimation(.easeOut(duration: 0.13)) { clunk = false } }
            withAnimation(.easeInOut(duration: 0.8)) { glint = true }
        }
        after(1.05) { lettersIn = true }
        after(1.5) { withAnimation(.easeOut(duration: 0.6)) { ruleIn = true } }
        after(1.75) { withAnimation(.easeOut(duration: 0.6)) { byIn = true } }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
