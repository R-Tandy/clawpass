import SwiftUI

/// Single source of truth for the app's name and user-facing copy.
/// Renaming the app means changing `name` here (plus the display name in the Xcode project).
enum AppBrand {
    static let name = "Layer"
    static let tagline = "Password manager for iPhone and desktop."
    static let desktopName = "\(name) for Desktop"
}

/// A colour theme. "Brass" is the original look; the others are alternatives chosen in Settings.
struct ThemeColors {
    let id: String
    let name: String
    let background, surface, surfaceRaised, stroke, accent, accentPressed, onAccent, textPrimary, textSecondary, textTertiary: Color
    /// Corner rounding relative to the standard design (0 = square corners) and the typeface family for the whole app.
    let radiusScale: CGFloat
    let fontDesign: Font.Design

    init(_ id: String, _ name: String, _ bg: String, _ surface: String, _ raised: String, _ stroke: String, _ accent: String, _ pressed: String, _ onAccent: String, _ t1: String, _ t2: String, _ t3: String, radius: CGFloat = 1, font: Font.Design = .default) {
        radiusScale = radius; fontDesign = font
        self.id = id; self.name = name
        background = Color(hex: bg); self.surface = Color(hex: surface); surfaceRaised = Color(hex: raised); self.stroke = Color(hex: stroke)
        self.accent = Color(hex: accent); accentPressed = Color(hex: pressed); self.onAccent = Color(hex: onAccent)
        textPrimary = Color(hex: t1); textSecondary = Color(hex: t2); textTertiary = Color(hex: t3)
    }

    static let all: [ThemeColors] = [
        // Brass: the original gold on near-black, with serif type and squarer corners for the steampunk feel.
        ThemeColors("brass", "Brass", "0B0C10", "15171C", "1D2027", "2A2D36", "C5A059", "A98A47", "0B0C10", "ECEDEF", "9AA3B2", "6B7280", radius: 0.6, font: .serif),
        // Layer: graphite with a restrained steel-cyan instead of bright cyan everywhere.
        ThemeColors("layer", "Layer", "0F1114", "161A1F", "1D2229", "2A2F37", "6FB3C4", "4F93A4", "0F1114", "F2F4F7", "8A919C", "6B727D"),
        // Terminal: pure black, phosphor green, monospace, no rounded corners.
        ThemeColors("terminal", "Terminal", "000000", "000000", "050A05", "0F3D1C", "2BD45F", "1E9D45", "000000", "46D977", "2FA155", "1F6B39", radius: 0, font: .monospaced),
        // Midnight: deep blue over true black.
        ThemeColors("midnight", "Midnight", "03050B", "0B1226", "121C38", "1F2C52", "6EA8FF", "3F78D6", "03050B", "E8EEFF", "8A9BC4", "5C6B94")
    ]
}

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    private static let key = "layer.theme"

    @Published private(set) var current: ThemeColors

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        current = ThemeColors.all.first { $0.id == saved } ?? ThemeColors.all[0]
    }

    func select(_ id: String) {
        guard let theme = ThemeColors.all.first(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: Self.key)
        current = theme
    }
}

/// Every view reads colours from here; the root view is rebuilt when the theme changes.
enum Palette {
    private static var theme: ThemeColors { ThemeStore.shared.current }
    static var background: Color { theme.background }
    static var surface: Color { theme.surface }
    static var surfaceRaised: Color { theme.surfaceRaised }
    static var stroke: Color { theme.stroke }
    static var accent: Color { theme.accent }
    static var accentPressed: Color { theme.accentPressed }
    static var onAccent: Color { theme.onAccent }
    static var textPrimary: Color { theme.textPrimary }
    static var textSecondary: Color { theme.textSecondary }
    static var textTertiary: Color { theme.textTertiary }
    static func r(_ base: CGFloat) -> CGFloat { base * theme.radiusScale }
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
                RoundedRectangle(cornerRadius: Palette.r(14), style: .continuous)
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
                RoundedRectangle(cornerRadius: Palette.r(14), style: .continuous)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Palette.r(14), style: .continuous)
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
                RoundedRectangle(cornerRadius: Palette.r(16), style: .continuous)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Palette.r(16), style: .continuous)
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
                RoundedRectangle(cornerRadius: Palette.r(12), style: .continuous)
                    .fill(Palette.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: Palette.r(12), style: .continuous)
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
            RoundedRectangle(cornerRadius: Palette.r(12), style: .continuous)
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
            RoundedRectangle(cornerRadius: Palette.r(size * 0.28), style: .continuous)
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

// MARK: - Unlock photo

import AVFoundation
import CoreLocation

/// Takes a front-camera photo after a wrong password on the unlock screen, stamps it with the date,
/// time and location, and saves it on the phone (see UnlockPhotosView for the list). Successful unlocks save nothing.
final class UnlockPhotoService: NSObject, AVCapturePhotoCaptureDelegate, CLLocationManagerDelegate {
    static let shared = UnlockPhotoService()
    static let enabledKey = "layer.unlockPhoto"

    private let output = AVCapturePhotoOutput()
    private let locationManager = CLLocationManager()
    private var session: AVCaptureSession?
    private var photoContinuation: CheckedContinuation<Data?, Never>?
    private var capturing = false
    private let stateLock = NSLock()

    /// Resumes the pending photo request exactly once; later calls (timeout vs delegate) are no-ops.
    private func finishPhoto(_ data: Data?) {
        stateLock.lock()
        let c = photoContinuation
        photoContinuation = nil
        stateLock.unlock()
        c?.resume(returning: data)
    }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Layer/captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Call after a wrong password; the photo is taken and saved in the background.
    func captureWrongPassword() {
        guard enabled, !capturing else { return }   // one capture at a time; rapid wrong tries must not stack sessions
        capturing = true
        let when = Date()
        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.requestLocation()
        Task.detached { [self] in
            defer { DispatchQueue.main.async { self.capturing = false } }
            guard let data = await self.captureFrame() else { return }
            let location = self.locationManager.location
            guard let stamped = Self.stamp(data, when: when, location: location) else { return }
            Self.save(stamped, when: when, location: location)
        }
    }

    private func captureFrame() async -> Data? {
        guard await cameraAllowed(),
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        let session = AVCaptureSession()
        guard session.canAddInput(input), session.canAddOutput(output) else { return nil }
        session.addInput(input)
        session.addOutput(output)
        self.session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        // Give the sensor a moment to settle exposure before the frame is taken.
        try? await Task.sleep(nanoseconds: 600_000_000)
        // capturePhoto raises an Objective-C exception (a crash) if the session is not running yet.
        var waited = 0
        while !session.isRunning && waited < 20 { try? await Task.sleep(nanoseconds: 100_000_000); waited += 1 }
        guard session.isRunning, output.connection(with: .video) != nil else {
            session.stopRunning(); self.session = nil
            return nil
        }
        let data: Data? = await withCheckedContinuation { continuation in
            stateLock.lock(); self.photoContinuation = continuation; stateLock.unlock()
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            // If the camera never answers, give up so the task (and the session) cannot hang forever.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in self?.finishPhoto(nil) }
        }
        session.stopRunning()
        self.session = nil
        return data
    }

    private func cameraAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        finishPhoto(error == nil ? photo.fileDataRepresentation() : nil)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private static func stamp(_ data: Data, when: Date, location: CLLocation?) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let bar = max(46, size.height * 0.11)
        let renderer = UIGraphicsImageRenderer(size: size)
        let stamped = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            UIColor(white: 0.03, alpha: 0.78).setFill()
            UIRectFill(CGRect(x: 0, y: size.height - bar, width: size.width, height: bar))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: bar * 0.3, weight: .regular),
                .foregroundColor: UIColor(white: 0.92, alpha: 1)
            ]
            let place = location.map { String(format: "%.5f, %.5f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "Location unavailable"
            DateFormatter.localizedString(from: when, dateStyle: .medium, timeStyle: .medium)
                .draw(at: CGPoint(x: 12, y: size.height - bar * 0.9), withAttributes: attrs)
            "\(place)  ·  WRONG PASSWORD".draw(at: CGPoint(x: 12, y: size.height - bar * 0.5), withAttributes: attrs)
        }
        return stamped.jpegData(compressionQuality: 0.82)
    }

    private static func save(_ jpeg: Data, when: Date, location: CLLocation?) {
        let name = "\(Int(when.timeIntervalSince1970 * 1000)).jpg"
        let dir = directory
        try? jpeg.write(to: dir.appendingPathComponent(name))
        var entry: [String: Any] = ["file": name, "taken_at": ISO8601DateFormatter().string(from: when)]
        if let c = location { entry["lat"] = c.coordinate.latitude; entry["lon"] = c.coordinate.longitude }
        guard let line = try? JSONSerialization.data(withJSONObject: entry), let text = String(data: line, encoding: .utf8) else { return }
        let log = dir.appendingPathComponent("log.jsonl")
        let existing = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try? (existing + text + "\n").write(to: log, atomically: true, encoding: .utf8)
    }

    /// Newest first.
    static func entries() -> [(file: String, takenAt: String, place: String)] {
        let text = (try? String(contentsOf: directory.appendingPathComponent("log.jsonl"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { line in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let file = obj["file"] as? String else { return nil }
            let place: String
            if let lat = obj["lat"] as? Double, let lon = obj["lon"] as? Double {
                place = String(format: "%.5f, %.5f", lat, lon)
            } else {
                place = "Location unavailable"
            }
            return (file, obj["taken_at"] as? String ?? "", place)
        }.reversed()
    }

    static func delete(_ file: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        let log = directory.appendingPathComponent("log.jsonl")
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let kept = text.split(separator: "\n").filter { !$0.contains("\"\(file)\"") }
        try? (kept.map(String.init).joined(separator: "\n") + (kept.isEmpty ? "" : "\n")).write(to: log, atomically: true, encoding: .utf8)
    }
}

struct UnlockPhotosView: View {
    @State private var items = UnlockPhotoService.entries()

    var body: some View {
        List {
            if items.isEmpty {
                Text("No photos yet. One is taken after each wrong password on the unlock screen.")
                    .foregroundColor(Palette.textSecondary)
            }
            ForEach(items, id: \.file) { item in
                VStack(alignment: .leading, spacing: 6) {
                    if let image = UIImage(contentsOfFile: UnlockPhotoService.directory.appendingPathComponent(item.file).path) {
                        Image(uiImage: image).resizable().scaledToFit().cornerRadius(8)
                    }
                    Text("Wrong password")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Palette.danger)
                    Text(item.takenAt).font(.caption).foregroundColor(Palette.textSecondary)
                    Text(item.place).font(.caption).foregroundColor(Palette.textSecondary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        UnlockPhotoService.delete(item.file)
                        items = UnlockPhotoService.entries()
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Unlock photos")
    }
}


extension Palette {
    /// Explicit themed font for list rows, which do not reliably inherit the app-wide font design.
    static func font(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        Font.system(style, design: ThemeStore.shared.current.fontDesign).weight(weight)
    }
}

extension View {
    /// Lets the keyboard be dragged away so the Unlock button is never stuck behind it.
    @ViewBuilder func keyboardDismissOnScroll() -> some View {
        if #available(iOS 16.0, *) { self.scrollDismissesKeyboard(.interactively) } else { self }
    }

    /// Applies the current theme's typeface to everything below.
    @ViewBuilder func themeFont() -> some View {
        if #available(iOS 16.1, *) { self.fontDesign(ThemeStore.shared.current.fontDesign) } else { self }
    }
}
