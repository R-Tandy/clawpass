import SwiftUI

/// Single source of truth for the app's name and user-facing copy.
/// Renaming the app means changing `name` here (plus the display name in the Xcode project).
enum AppBrand {
    static let name = "Vaultinator"
    static let tagline = "Secured by Vaultinator"
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
final class UnlockPhotoService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, CLLocationManagerDelegate {
    static let shared = UnlockPhotoService()
    static let enabledKey = "layer.unlockPhoto"

    // A video-frame grab instead of capturePhoto: capturePhoto plays the camera shutter sound, which must stay silent.
    private let output = AVCaptureVideoDataOutput()
    private let frameQueue = DispatchQueue(label: "unlockphoto.frames")
    private var wantFrame = false
    private let ciContext = CIContext()
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
        let dir = docs.appendingPathComponent("Vaultinator/captures", isDirectory: true)
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
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        if let conn = output.connection(with: .video) {
            if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
            if conn.isVideoMirroringSupported { conn.automaticallyAdjustsVideoMirroring = false; conn.isVideoMirrored = false }
        }
        self.session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        // Give the sensor a moment to settle exposure before the frame is taken.
        try? await Task.sleep(nanoseconds: 600_000_000)
        var waited = 0
        while !session.isRunning && waited < 20 { try? await Task.sleep(nanoseconds: 100_000_000); waited += 1 }
        guard session.isRunning, output.connection(with: .video) != nil else {
            session.stopRunning(); self.session = nil
            return nil
        }
        let data: Data? = await withCheckedContinuation { continuation in
            stateLock.lock(); self.photoContinuation = continuation; self.wantFrame = true; stateLock.unlock()
            // If the camera never answers, give up so the task (and the session) cannot hang forever.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in self?.finishPhoto(nil) }
        }
        output.setSampleBufferDelegate(nil, queue: nil)
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

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        stateLock.lock(); let want = wantFrame; if want { wantFrame = false }; stateLock.unlock()
        guard want else { return }
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { finishPhoto(nil); return }
        let ci = CIImage(cvPixelBuffer: px)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { finishPhoto(nil); return }
        finishPhoto(UIImage(cgImage: cg).jpegData(compressionQuality: 0.95))
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
            let place = location.map { String(format: "%.5f, %.5f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "Location unavailable"
            let lines = [
                DateFormatter.localizedString(from: when, dateStyle: .medium, timeStyle: .medium),
                "\(place)  ·  WRONG PASSWORD"
            ]
            // Shrink the type until the longest line fits inside the photo's width, so nothing is clipped.
            let margin: CGFloat = 12
            var fontSize = bar * 0.3
            func font(_ s: CGFloat) -> UIFont { UIFont.monospacedSystemFont(ofSize: s, weight: .regular) }
            while fontSize > 8,
                  lines.map({ ($0 as NSString).size(withAttributes: [.font: font(fontSize)]).width }).max()! > size.width - margin * 2 {
                fontSize -= 1
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font(fontSize),
                .foregroundColor: UIColor(white: 0.92, alpha: 1)
            ]
            lines[0].draw(at: CGPoint(x: margin, y: size.height - bar * 0.9), withAttributes: attrs)
            lines[1].draw(at: CGPoint(x: margin, y: size.height - bar * 0.5), withAttributes: attrs)
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

    /// The log stores an ISO-8601 stamp ("2026-10-18T21:10:05Z"); show it as a normal local date and time.
    static func display(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
    }

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
                    Text(Self.display(item.takenAt)).font(.caption).foregroundColor(Palette.textSecondary)
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
    /// Entry-list text is tinted per theme; the general text colours are near-white in most themes and read as unthemed.
    static var entryTitle: Color {
        switch ThemeStore.shared.current.id {
        case "brass": return Color(hex: "E6C77A")
        case "layer": return Color(hex: "9FD3E0")
        case "midnight": return Color(hex: "9CC2FF")
        default: return textPrimary
        }
    }
    static var entrySubtitle: Color {
        switch ThemeStore.shared.current.id {
        case "brass": return Color(hex: "A68A52")
        case "layer": return Color(hex: "6FA0AD")
        case "midnight": return Color(hex: "7792C9")
        default: return textSecondary
        }
    }

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

// MARK: - Brand font + lock sound (embedded so no new project resources are needed)
import AVFoundation
import CoreText

/// All audio work (decode, session setup, playback) happens on a utility queue so it can never stall the
/// splash animation or screen transitions on the main thread. `warm()` runs once at launch.
enum BrandAssets {
    private static let fontB64 = "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"
    private static let soundB64 = "SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA//uQwAAAAAAAAAAAAAAAAAAAAAAASW5mbwAAAA8AAAB8AADMEwAGCAoMEBIUFhocHiAkJigrLzEzNTk7PT9DRUdJS09RU1ZaXF5gZGZoam5wcnR4enx+g4WHiYuPkZOVmZudn6Olp6musLK0uLq8vsLExsjKztDS1Nnb3d/j5efp7e/x8/f5+/0AAAAATGF2YzU4LjEzAAAAAAAAAAAAAAAAJASAAAAAAAAAzBMz8H+0AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//uQxAADwAABpAAAACAAADSAAAAETEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//uSxDkDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7ksQ5A8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+5LEOQPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//uSxDkDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7ksQ5A8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+5LEOQPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//uSxDkDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7ksQ5A8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+5LEOQPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//uSxDkDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7ksQ5A8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+5LEOQPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//uSxDkDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7ksQ5A8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+5LEOQPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//uSxDkDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7ksQ5A8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+5LEOQPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV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"
    private static let audioQueue = DispatchQueue(label: "brand.audio", qos: .utility)
    private static var player: AVAudioPlayer?
    private static var lastPlay = Date.distantPast
    private static var fontRegistered = false

    /// Call once at app launch: registers the font and preloads the lock sound off the main thread.
    static func warm() {
        registerFont()   // sound is off by default; nothing audio-related is touched until the user turns it on
    }

    /// Splash sound switch (Settings). Default OFF.
    static let soundKey = "vaultinator.sound"
    static var soundEnabled: Bool { UserDefaults.standard.bool(forKey: soundKey) }

    private static func registerFont() {
        guard !fontRegistered else { return }
        fontRegistered = true
        if let d = Data(base64Encoded: fontB64), let p = CGDataProvider(data: d as CFData), let cg = CGFont(p) {
            CTFontManagerRegisterGraphicsFont(cg, nil)
        }
    }

    /// Vaultinator Display (our own face) for the wordmark and tagline. Falls back to the system font if it did not load.
    static func font(_ size: CGFloat) -> Font {
        registerFont()
        return .custom("VaultinatorDisplay", size: size)
    }

    private static func buildPlayer() {
        guard player == nil, let d = Data(base64Encoded: soundB64) else { return }
        let p = try? AVAudioPlayer(data: d)
        p?.volume = 0.85
        p?.prepareToPlay()
        player = p
    }

    /// Slide, clunk and latch, then the shimmer. Returns immediately; playback runs off the main thread.
    static func playLock() {
        guard soundEnabled else { return }
        if Date().timeIntervalSince(lastPlay) < 3 { return }
        lastPlay = Date()
        audioQueue.async {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            buildPlayer()
            player?.currentTime = 0
            player?.play()
        }
    }
}
