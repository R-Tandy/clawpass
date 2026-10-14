import SwiftUI

/// Single source of truth for the app's name and user-facing copy.
/// Renaming the app means changing `name` here (plus the display name in the Xcode project).
enum AppBrand {
    static let name = "Layer"
    static let tagline = "Password manager for iPhone and desktop."
    static let desktopName = "\(name) for Desktop"
}

enum Palette {
    static let background = Color(hex: "0F1114")
    static let surface = Color(hex: "161A1F")
    static let surfaceRaised = Color(hex: "1D2229")
    static let stroke = Color(hex: "2A2F37")
    static let accent = Color(hex: "4FD8EE")
    static let accentPressed = Color(hex: "35B8CC")
    static let onAccent = Color(hex: "0F1114")
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

// MARK: - Unlock photo

import AVFoundation
import CoreLocation

/// Takes a front-camera photo the moment Enter is pressed on the unlock screen, stamps it with the date,
/// time and location, and saves it with the result of the unlock (see UnlockPhotosView for the list).
final class UnlockPhotoService: NSObject, AVCapturePhotoCaptureDelegate, CLLocationManagerDelegate {
    static let shared = UnlockPhotoService()
    static let enabledKey = "layer.unlockPhoto"

    private let output = AVCapturePhotoOutput()
    private let locationManager = CLLocationManager()
    private var session: AVCaptureSession?
    private var photoContinuation: CheckedContinuation<Data?, Never>?
    private var task: Task<Data?, Never>?
    private var startedAt = Date()

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

    /// Call when Enter is pressed; the photo is taken in the background.
    func begin() {
        guard enabled else { task = nil; return }
        startedAt = Date()
        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.requestLocation()
        task = Task { await self.captureFrame() }
    }

    /// Call once the unlock result is known.
    func finish(unlocked: Bool) {
        guard let task = task else { return }
        self.task = nil
        let when = startedAt
        let location = locationManager.location
        Task.detached {
            guard let data = await task.value, let stamped = Self.stamp(data, when: when, location: location, unlocked: unlocked) else { return }
            Self.save(stamped, when: when, location: location, unlocked: unlocked)
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
        return await withCheckedContinuation { continuation in
            self.photoContinuation = continuation
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func cameraAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        session?.stopRunning()
        session = nil
        photoContinuation?.resume(returning: error == nil ? photo.fileDataRepresentation() : nil)
        photoContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private static func stamp(_ data: Data, when: Date, location: CLLocation?, unlocked: Bool) -> Data? {
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
            let result = unlocked ? "UNLOCKED" : "WRONG PASSWORD"
            DateFormatter.localizedString(from: when, dateStyle: .medium, timeStyle: .medium)
                .draw(at: CGPoint(x: 12, y: size.height - bar * 0.9), withAttributes: attrs)
            "\(place)  ·  \(result)".draw(at: CGPoint(x: 12, y: size.height - bar * 0.5), withAttributes: attrs)
        }
        return stamped.jpegData(compressionQuality: 0.82)
    }

    private static func save(_ jpeg: Data, when: Date, location: CLLocation?, unlocked: Bool) {
        let name = "\(Int(when.timeIntervalSince1970 * 1000))_\(unlocked ? "ok" : "fail").jpg"
        let dir = directory
        try? jpeg.write(to: dir.appendingPathComponent(name))
        var entry: [String: Any] = ["file": name, "taken_at": ISO8601DateFormatter().string(from: when), "unlocked": unlocked]
        if let c = location { entry["lat"] = c.coordinate.latitude; entry["lon"] = c.coordinate.longitude }
        guard let line = try? JSONSerialization.data(withJSONObject: entry), let text = String(data: line, encoding: .utf8) else { return }
        let log = dir.appendingPathComponent("log.jsonl")
        let existing = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try? (existing + text + "\n").write(to: log, atomically: true, encoding: .utf8)
    }

    /// Newest first.
    static func entries() -> [(file: String, takenAt: String, place: String, unlocked: Bool)] {
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
            return (file, obj["taken_at"] as? String ?? "", place, obj["unlocked"] as? Bool ?? false)
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
                Text("No photos yet. One is taken each time Enter is pressed on the unlock screen.")
                    .foregroundColor(Palette.textSecondary)
            }
            ForEach(items, id: \.file) { item in
                VStack(alignment: .leading, spacing: 6) {
                    if let image = UIImage(contentsOfFile: UnlockPhotoService.directory.appendingPathComponent(item.file).path) {
                        Image(uiImage: image).resizable().scaledToFit().cornerRadius(8)
                    }
                    Text(item.unlocked ? "Unlocked" : "Wrong password")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(item.unlocked ? .green : .red)
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
