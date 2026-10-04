import SwiftUI
import AVFoundation

// SINGLETON: Lifts the session out of the View lifecycle to prevent
// accidental deallocation or reset during SwiftUI re-renders.
class CameraManager: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    static let shared = CameraManager()
    
    var session: AVCaptureSession?
    var onCodeFound: ((String) -> Void)?
    
    private override init() {
        super.init()
    }
    
    func setupAndStart(previewLayer: AVCaptureVideoPreviewLayer) {
        SyncService.shared.log("[CameraManager] Initializing persistent session...")
        
        let session = AVCaptureSession()
        self.session = session
        
        session.beginConfiguration()
        do {
            guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
                SyncService.shared.log("[CameraManager] FAIL: No camera available")
                session.commitConfiguration()
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                SyncService.shared.log("[CameraManager] FAIL: Cannot add input")
                session.commitConfiguration()
                return
            }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue(label: "com.clawpass.qr.metadata", qos: .userInteractive))
                output.metadataObjectTypes = [.qr]
                SyncService.shared.log("[CameraManager] Metadata output bound to Singleton")
            } else {
                SyncService.shared.log("[CameraManager] FAIL: Cannot add output")
                session.commitConfiguration()
                return
            }

            previewLayer.session = session
            
            DispatchQueue.global(qos: .userInteractive).async {
                session.startRunning()
                SyncService.shared.log("[CameraManager] session.startRunning() called. isRunning: \(session.isRunning)")
            }
        } catch {
            SyncService.shared.log("[CameraManager] CRITICAL error: \(error)")
        }
        session.commitConfiguration()
        SyncService.shared.log("[CameraManager] Configuration committed.")
    }
    
    func stop() {
        session?.stopRunning()
        session = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // PANIC LOG: This is the ultimate test of the pipeline.
        SyncService.shared.log("[CameraManager-DEBUG] Delegate fired. Objects: \(metadataObjects.count)")

        if metadataObjects.isEmpty { return }

        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let stringValue = metadataObject.stringValue {
            SyncService.shared.log("[CameraManager] SUCCESS: Found QR code: \(stringValue)")
            DispatchQueue.main.async {
                self.onCodeFound?(stringValue)
            }
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCodeFound: (String) -> Void
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        
        // Bind singleton callback to the closure
        CameraManager.shared.onCodeFound = { code in
            onCodeFound(code)
            presentationMode.wrappedValue.dismiss()
        }
        
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

class ScannerViewController: UIViewController {
    let statusLabel = UILabel()
    let overlayView = UIView()
    let scanBox = UIView()
    let statusIndicator = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.frame = self.view.frame
        previewLayer.videoGravity = .resizeAspectFill
        self.view.layer.insertSublayer(previewLayer, at: 0)
        
        self.statusLabel.text = "Scanning for connection QR..."
        
        // Trigger the singleton to take over the hardware
        CameraManager.shared.setupAndStart(previewLayer: previewLayer)
    }

    private func setupUI() {
        statusLabel.text = "Initializing Camera..."
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.frame = CGRect(x: 20, y: view.frame.height - 100, width: view.frame.width - 40, height: 40)
        view.addSubview(statusLabel)

        statusIndicator.backgroundColor = .red
        statusIndicator.layer.cornerRadius = 6
        statusIndicator.frame = CGRect(x: view.frame.width - 30, y: 50, width: 12, height: 12)
        view.addSubview(statusIndicator)

        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.frame = view.bounds
        view.addSubview(overlayView)

        let boxSize: CGFloat = 250
        scanBox.frame = CGRect(
            x: (view.frame.width - boxSize) / 2,
            y: (view.frame.height - boxSize) / 2,
            width: boxSize,
            height: boxSize
        )
        scanBox.layer.borderColor = UIColor(red: 0.77, green: 0.63, blue: 0.35, alpha: 1.0).cgColor
        scanBox.layer.borderWidth = 4
        scanBox.backgroundColor = .clear
        overlayView.addSubview(scanBox)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        CameraManager.shared.stop()
    }
}
