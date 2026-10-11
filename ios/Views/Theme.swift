import SwiftUI

/// Single source of truth for the app's name and user-facing copy.
/// Renaming the app means changing `name` here (plus the display name in the Xcode project).
enum AppBrand {
    static let name = "Layer"
    static let tagline = "Password manager for iPhone and desktop."
    static let desktopName = "\(name) for Desktop"
}

enum Palette {
    static let background = Color(hex: "0B0C10")
    static let surface = Color(hex: "15171C")
    static let surfaceRaised = Color(hex: "1D2027")
    static let stroke = Color(hex: "2A2D36")
    static let accent = Color(hex: "C5A059")
    static let accentPressed = Color(hex: "A98A47")
    static let onAccent = Color(hex: "0B0C10")
    static let textPrimary = Color(hex: "ECEDEF")
    static let textSecondary = Color(hex: "9AA3B2")
    static let textTertiary = Color(hex: "6B7280")
    static let success = Color(hex: "34C759")
    static let danger = Color(hex: "FF5A52")
    static let warning = Color(hex: "FFB340")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(configuration.isPressed ? Palette.accentPressed : Palette.accent)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(Palette.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Palette.accent.opacity(0.6), lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Palette.stroke, lineWidth: 1)
                    )
            )
    }
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Palette.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}

/// Labeled text input with a consistent look. Pass `secure: true` for passwords.
struct FieldRow: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var secure: Bool = false
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(Palette.textSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(capitalization)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Palette.stroke, lineWidth: 1)
                    )
            )
        }
    }
}

struct InlineBanner: View {
    enum Kind { case error, info, success }
    let kind: Kind
    let message: String

    private var color: Color {
        switch kind {
        case .error: return Palette.danger
        case .info: return Palette.warning
        case .success: return Palette.success
        }
    }

    private var icon: String {
        switch kind {
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.14))
        )
        .accessibilityElement(children: .combine)
    }
}

/// Brand mark used on the welcome, connecting and unlock screens.
struct BrandMark: View {
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Palette.accent, Palette.accentPressed],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .shadow(color: Palette.accent.opacity(0.35), radius: 18, y: 6)
            Image(systemName: "key.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(Palette.onAccent)
                .rotationEffect(.degrees(-45))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Password strength

enum PasswordStrength {
    case empty, weak, fair, strong

    init(_ password: String) {
        if password.isEmpty { self = .empty; return }
        var classes = 0
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { classes += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { classes += 1 }
        let score = password.count + classes * 3
        switch score {
        case ..<14: self = .weak
        case ..<24: self = .fair
        default: self = .strong
        }
    }

    var label: String {
        switch self {
        case .empty: return ""
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        }
    }

    var color: Color {
        switch self {
        case .empty: return Palette.textTertiary
        case .weak: return Palette.danger
        case .fair: return Palette.warning
        case .strong: return Palette.success
        }
    }

    var fraction: Double {
        switch self {
        case .empty: return 0
        case .weak: return 0.33
        case .fair: return 0.66
        case .strong: return 1
        }
    }
}

struct StrengthMeter: View {
    let password: String

    var body: some View {
        let strength = PasswordStrength(password)
        if strength != .empty {
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.stroke)
                        Capsule().fill(strength.color).frame(width: geo.size.width * strength.fraction)
                    }
                }
                .frame(height: 5)
                Text(strength.label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(strength.color)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Password strength \(strength.label)")
        }
    }
}
