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
    private static let soundB64 = "SUQzBAAAAAAtTVRTU0UAAAAPAAADTGF2ZjYwLjE2LjEwMABHRU9CAAAtKgAAA2FwcGxpY2F0aW9uL2MycGEAYzJwYQBjMnBhIG1hbmlmZXN0IHN0b3JlAAAAFn9qdW1iAAAAHmp1bWRjMnBhABEAEIAAAKoAOJtxA2MycGEAAAAWWWp1bWIAAABHanVtZGMybWEAEQAQgAAAqgA4m3EDdXJuOmMycGE6NmQ0NWVjNTUtOWE3Ni00YTViLWE1N2EtZTViZTUwM2E4ZmM4AAAAA5RqdW1iAAAAKWp1bWRjMmFzABEAEIAAAKoAOJtxA2MycGEuYXNzZXJ0aW9ucwAAAAC5anVtYgAAAERqdW1kY2JvcgARABCAAACqADibcRNjMnBhLmluZ3JlZGllbnQudjMAAAAAGGMyc2hcTRWndPdFzR+Zvn3O8BZwAAAAbWNib3KjaWRjOmZvcm1hdGphdWRpby9tcGVnamluc3RhbmNlSUR4LHhtcDppaWQ6NGY4OWYwNzUtZTQ5NS00ZDYxLTkwYzMtZjEzZGI1YTE5YzIybHJlbGF0aW9uc2hpcGhwYXJlbnRPZgAAAeJqdW1iAAAAQWp1bWRjYm9yABEAEIAAAKoAOJtxE2MycGEuYWN0aW9ucy52MgAAAAAYYzJzaJhdsYrQO9VxH0J5AvgKgu8AAAGZY2JvcqJnYWN0aW9uc4KiZmFjdGlvbmtjMnBhLm9wZW5lZGpwYXJhbWV0ZXJzoWtpbmdyZWRpZW50c4GiY3VybHgtc2VsZiNqdW1iZj1jMnBhLmFzc2VydGlvbnMvYzJwYS5pbmdyZWRpZW50LnYzZGhhc2hYIO7Zuit3CrVxhnOA1ky+G7Fz0l4CuodnjhvHuDMzC8v4pGZhY3Rpb254HWNvbS5hbnRocm9waWMuY2xhdWRlLnByb3ZpZGVkanBhcmFtZXRlcnOheB9jb20uYW50aHJvcGljLm9yaWdpbi1jb25maWRlbmNlZ3Vua25vd25rZGVzY3JpcHRpb254ZkNsYXVkZSBwcm92aWRlZCB0aGlzIGZpbGUgYXQgdGhlIHJlcXVlc3Qgb2YgYSB1c2VyIGFuZCBtYXkgaGF2ZSBjcmVhdGVkIG9yIG1vZGlmaWVkIHRoZSBmaWxlIGNvbnRlbnRzLm1zb2Z0d2FyZUFnZW50oWRuYW1lZkNsYXVkZXJhbGxBY3Rpb25zSW5jbHVkZWT1AAAAyGp1bWIAAABAanVtZGNib3IAEQAQgAAAqgA4m3ETYzJwYS5oYXNoLmRhdGEAAAAAGGMyc2ijMe+tkWCaCc0P72dGkQsZAAAAgGNib3KlY2FsZ2ZzaGEyNTZjcGFkTQAAAAAAAAAAAAAAAABkaGFzaFggPruEhaE+Jnl7qHSCMGJjXcKb5hSjod/x9qajvAiFnktkbmFtZW5qdW1iZiBtYW5pZmVzdGpleGNsdXNpb25zgaJlc3RhcnQYWGZsZW5ndGgZFn8AAAI+anVtYgAAACdqdW1kYzJjbAARABCAAACqADibcQNjMnBhLmNsYWltLnYyAAAAAg9jYm9ypWNhbGdmc2hhMjU2aXNpZ25hdHVyZXhNc2VsZiNqdW1iZj0vYzJwYS91cm46YzJwYTo2ZDQ1ZWM1NS05YTc2LTRhNWItYTU3YS1lNWJlNTAzYThmYzgvYzJwYS5zaWduYXR1cmVqaW5zdGFuY2VJRHgseG1wOmlpZDpjODE3ZTVkOS1lMzQwLTQyMjUtYmU1OC02YmI0NzhjNTUyOWJyY3JlYXRlZF9hc3NlcnRpb25zg6JjdXJseC1zZWxmI2p1bWJmPWMycGEuYXNzZXJ0aW9ucy9jMnBhLmluZ3JlZGllbnQudjNkaGFzaFgg7tm6K3cKtXGGc4DWTL4bsXPSXgK6h2eOG8e4MzMLy/iiY3VybHgqc2VsZiNqdW1iZj1jMnBhLmFzc2VydGlvbnMvYzJwYS5hY3Rpb25zLnYyZGhhc2hYIMT1TQeJPt7dwfAOn81TTD+alCXKHsb9vlhMqvtlJukaomN1cmx4KXNlbGYjanVtYmY9YzJwYS5hc3NlcnRpb25zL2MycGEuaGFzaC5kYXRhZGhhc2hYIEAeNQQd0MKi0UH9LaDTgdMcs7EcurvQS7xTT46vPPQtdGNsYWltX2dlbmVyYXRvcl9pbmZvo2RuYW1lb0FudGhyb3BpYyBGaWxlc2d2ZXJzaW9uZTEuMC4wa3NwZWNWZXJzaW9uZTIuNC4wAAAQOGp1bWIAAAAoanVtZGMyY3MAEQAQgAAAqgA4m3EDYzJwYS5zaWduYXR1cmUAAAAQCGNib3LShFkCEqIBJhghWQIKMIICBjCCAY2gAwIBAgIUQOWgCu7COdC+uIP6BkIFPWdVEwAwCgYIKoZIzj0EAwMwSTEXMBUGA1UEChMOQW50aHJvcGljLCBQQkMxLjAsBgNVBAMTJUFudGhyb3BpYyBDb250ZW50IENyZWRlbnRpYWxzIFJvb3QgQ0EwHhcNMjYwODA3MTg0MzU2WhcNMjgwODA2MTk0MzU2WjBEMRcwFQYDVQQKEw5BbnRocm9waWMsIFBCQzEpMCcGA1UEAxMgQW50aHJvcGljIENsYXVkZSBDb250ZW50IFNpZ25pbmcwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASYegpry1AYBRTVNL1CpTlbROnY3dey+UrsF9C3phYrATN3ZHf93Mo8RQN0KOUuOn19P4oWNFWe5n2/She9N7eTo1gwVjAOBgNVHQ8BAf8EBAMCB4AwFQYDVR0lBA4wDAYKKwYBBAGD6F4CATAMBgNVHRMBAf8EAjAAMB8GA1UdIwQYMBaAFM5R4gSBTmRbI/jjxM+aPpzB11zCMAoGCCqGSM49BAMDA2cAMGQCMDFzHRSeAXrSy1WOzkbhPZ6Km2wGTmZ/2gK18k8BQGXyqz88Rdrz6CTX9flAnYNVxgIwcF9c3fVhqmJKpi+UhasNUMko69cyX6STPfta3Q8EjyzDjzoyrol46FP6VFHhvUcJoWNwYWRZDZ4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA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A4Av8AU8z+ggm//n5h5B//NExPoTyqp7HoAmxF0nC3tJn/96+pfmWa/B0wGULLtpF4w1tS1t261quV9R0JgAiMyX8fgs4SH/rPJF4AVhCt/WUgDIFxH/sNcAUA0kf/////+GdDw+VYB4ALAIAUxw//M0xP0Reqp/FmgkxEAt6ILFqf9EQ576TJTIUd/q+dFQKrtQI8CYPf8yFif9IAUr/+86Ok9/0AxENh/+txIyX//////8XxLV//NExPIUWqZ3HG4hJCoCUDAMfSD9QpPV/nnX+tQ1w25PsxNhsZtrJQUGrqFDh+aX+o6RBH8jw2Qr//QYjRBY1/1GIjEaKX/lwJRX//////j6G9VVw3AgAcKTghQL+sLD//NExPMXIqpRuFZnKUf8flWbpIyNGI3mAToNgRmg9IMbL6yZDpn/5GCYN9yKhZ0nE2/68QR/9Y+yv/6i8KySz//////8jhUZFQNKKBSIUIw/MgL9VKp/WZt+6CzUTih7//NExOkQyq57HmgixI6QqGr5YFFKnTF4INIi7b9YlwN3pflAOgLT/9anKQaqNv+kGXBUv/kaGJCQ//////9IYNQDMCACjhBIP0wTxG3+jojqEAzbWpZGCgVdILSxRjVR//M0xPgRSq5iTGgixNJgR2F7C4ip/y8F1Rv+RwFZf/65weT3/QDZiJP/1LC7yE//////86QlVQNAGAI9RPyAHWv/psLMCeN2//NExO0R4qpqfmgixK8nCdO1RFBWF9ZWAK7/6iaLxr+ZgO4t/+qmApt/0Seef/zALyj//////6zyAwAAwUTBwIH8BVTV/+PoXBvQMx5PueANlvHYHK/8fA4f6y63/1sd//M0xPgSuq5WXGggxBa//EO+g1qegXQOxtSkx//5KgIAABUy9YA/gKqRszqmANlD5WJQ2iTg5z+PwlLf8XAc7/sEyLLWQezL//NExOgSGq5SXGgkyJk6gvxLLdeyb0wVIZmf/phW///8lQgGZgD+IcVCU/yoPW6m/OQ7/jwPj/oeA0t/f6m/+gjEvb6iKAMLmUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVV//M0xPIPKqpWUlAayFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//M0xPAOIgJaXjgaUFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//M0xPIPagJOXBAaVFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//MkxO8JsgY9VAgOWFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//MUxOsAAAP8AAAAAFVVVVVVVVVVVVVV"
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
