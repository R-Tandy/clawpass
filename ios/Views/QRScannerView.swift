import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    var onCodeFound: (String) -> Void
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRScannerView

        init(_ parent: QRScannerView) {
            self.parent = parent
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            let logPrefix = "[QRScanner]"
            SyncService.shared.log("\(logPrefix) captureOutput triggered with \(metadataObjects.count) objects")
            
            if let metadataObject = metadataObjects.first {
                SyncService.shared.log("\(logPrefix) First object type: \(type(of: metadataObject))")
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { 
                    SyncService.shared.log("\(logPrefix) Object was not a machine readable code")
                    return 
                }
                guard let stringValue = readableObject.stringValue else { 
                    SyncService.shared.log("\(logPrefix) Readable object had no string value")
                    return 
                }
                
                SyncService.shared.log("\(logPrefix) SUCCESS: Found QR code with value: \(stringValue)")
                DispatchQueue.main.async {
                    self.parent.onCodeFound(stringValue)
                }
            }
        }
    }
}

class ScannerViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var delegate: AVCaptureMetadataOutputObjectsDelegate?
    private let metadataQueue = DispatchQueue(label: "com.clawpass.metadata", qos: .userInitiated)
    
    private let statusLabel = UILabel()
    private let overlayView = UIView()
    private let scanBox = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupUI()
        setupCamera()
    }

    private func setupUI() {
        // 1. Status Label
        statusLabel.text = "Initializing Camera..."
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.frame = CGRect(x: 20, y: view.frame.height - 100, width: view.frame.width - 40, height: 40)
        view.addSubview(statusLabel)

        // 2. Dark Overlay
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.frame = view.bounds
        view.addSubview(overlayView)

        // 3. Scanning Box
        let boxSize: CGFloat = 250
        scanBox.frame = CGRect(
            x: (view.frame.width - boxSize) / 2,
            y: (view.frame.height - boxSize) / 2,
            width: boxSize,
            height: boxSize
        )
        scanBox.layer.borderColor = UIColor(red: 0.77, green: 0.63, blue: 0.35, alpha: 1.0).cgColor // #C5A059
        scanBox.layer.borderWidth = 4
        scanBox.backgroundColor = .clear
        
        overlayView.addSubview(scanBox)
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        self.captureSession = session

        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .authorized {
            DispatchQueue.global(qos: .userInitiated).async {
                self.triggerHardwareSetup(session: session)
            }
        } else if authStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.global(qos: .userInitiated).async {
                        self?.triggerHardwareSetup(session: session)
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.statusLabel.text = "Access Denied"
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.statusLabel.text = "Access Denied"
            }
        }
    }

    private func triggerHardwareSetup(session: AVCaptureSession) {
        do {
            guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
                SyncService.shared.log("[QRScanner] No camera available")
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                SyncService.shared.log("[QRScanner] Could not add video input")
                return
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(delegate, queue: metadataQueue)
                metadataOutput.metadataObjectTypes = [.qr]
                SyncService.shared.log("[QRScanner] Metadata output added successfully")
            } else {
                SyncService.shared.log("[QRScanner] Could not add metadata output")
                return
            }

            session.startRunning()
            SyncService.shared.log("[QRScanner] Session startRunning() called")
            
            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.frame = self.view.frame
                previewLayer.videoGravity = .resizeAspectFill
                self.view.layer.insertSublayer(previewLayer, at: 0)
                
                self.statusLabel.text = "Align QR code within the box"
            }
            SyncService.shared.log("[QRScanner] Session started automatically and layer attached")
        } catch {
            SyncService.shared.log("[QRScanner] Hardware setup error: \(error)")
            DispatchQueue.main.async {
                self.statusLabel.text = "Hardware Error"
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}
