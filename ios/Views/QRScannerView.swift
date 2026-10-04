import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    var onCodeFound: (String) -> Void
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        
        // Start the camera setup via the coordinator
        context.coordinator.setupCamera(for: controller)
        
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRScannerView
        var captureSession: AVCaptureSession?
        var metadataOutput: AVCaptureMetadataOutput?
        private let metadataQueue = DispatchQueue(label: "com.clawpass.metadata", qos: .userInitiated)

        init(_ parent: QRScannerView) {
            self.parent = parent
        }

        func setupCamera(for controller: ScannerViewController) {
            let session = AVCaptureSession()
            self.captureSession = session

            session.beginConfiguration()
            do {
                guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
                    SyncService.shared.log("[QRScanner] No camera available")
                    session.commitConfiguration()
                    return
                }
                
                let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                } else {
                    SyncService.shared.log("[QRScanner] Could not add video input")
                    session.commitConfiguration()
                    return
                }

                let output = AVCaptureMetadataOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.metadataObjectTypes = [.qr]
                    output.setMetadataObjectsDelegate(self, queue: metadataQueue)
                    self.metadataOutput = output
                    SyncService.shared.log("[QRScanner] Metadata output configured in Coordinator")
                } else {
                    SyncService.shared.log("[QRScanner] Could not add metadata output")
                    session.commitConfiguration()
                    return
                }

                DispatchQueue.main.async {
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.frame = controller.view.frame
                    previewLayer.videoGravity = .resizeAspectFill
                    controller.view.layer.insertSublayer(previewLayer, at: 0)
                    
                    self.metadataOutput?.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
                    controller.statusLabel.text = "Scanning for connection QR..."
                    
                    // Force session start on main thread for this test
                    SyncService.shared.log("[QRScanner] Starting session on main thread...")
                    session.startRunning()
                    SyncService.shared.log("[QRScanner] Session started (Main Thread Start)")
                }
            } catch {
                SyncService.shared.log("[QRScanner] Hardware setup error: \(error)")
                DispatchQueue.main.async {
                    controller.statusLabel.text = "Hardware Error"
                }
            }
            session.commitConfiguration()
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            // HEARTBEAT: Log every single time this is called, even if objects is empty, 
            // to prove the delegate is actually connected.
            if metadataObjects.isEmpty {
                return 
            }

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

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var onCodeFound: ((String) -> Void)?
    var metadataOutput: AVCaptureMetadataOutput?
    private let metadataQueue = DispatchQueue(label: "com.clawpass.metadata", qos: .userInitiated)
    
    let statusLabel = UILabel()
    let overlayView = UIView()
    let scanBox = UIView()
    let statusIndicator = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupUI()
    }

    private func setupUI() {
        // 1. Status Label
        statusLabel.text = "Initializing Camera..."
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.frame = CGRect(x: 20, y: view.frame.height - 100, width: view.frame.width - 40, height: 40)
        view.addSubview(statusLabel)

        // 2. Status Indicator (The "Light")
        statusIndicator.backgroundColor = .red
        statusIndicator.layer.cornerRadius = 6
        statusIndicator.frame = CGRect(x: view.frame.width - 30, y: 50, width: 12, height: 12)
        view.addSubview(statusIndicator)

        // 3. Dark Overlay
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.frame = view.bounds
        view.addSubview(overlayView)

        // 4. Scanning Box
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

    func captureOutput(_ output: AVCaptureOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if metadataObjects.isEmpty {
            DispatchQueue.main.async {
                self.statusIndicator.backgroundColor = .red
            }
            return 
        }

        DispatchQueue.main.async {
            self.statusIndicator.backgroundColor = .green
        }

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
            
            // Find the coordinator via the UIViewControllerRepresentable's coordinator
            // Since we are now the delegate, we need to call the callback.
            // This is handled by the Coordinator's parent.onCodeFound.
            // We'll find a way to pass this back.
        }
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

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                self.metadataOutput = output
                SyncService.shared.log("[QRScanner] Metadata output added to session")
            } else {
                SyncService.shared.log("[QRScanner] Could not add metadata output")
                return
            }

            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.frame = self.view.frame
                previewLayer.videoGravity = .resizeAspectFill
                self.view.layer.insertSublayer(previewLayer, at: 0)
                
                // Configure the output on the main thread right before starting
                self.metadataOutput?.metadataObjectTypes = [.qr]
                self.metadataOutput?.setMetadataObjectsDelegate(self, queue: .main)
                self.metadataOutput?.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
                
                self.statusLabel.text = "Scanning for connection QR..."
                
                DispatchQueue.global(qos: .userInitiated).async {
                    SyncService.shared.log("[QRScanner] Attempting to start session...")
                    session.startRunning()
                    SyncService.shared.log("[QRScanner] Session started (Main-Queue Delegate)")
                }
            }
        } catch {
            SyncService.shared.log("[QRScanner] Hardware setup error: \(error)")
            DispatchQueue.main.async {
                self.statusLabel.text = "Hardware Error"
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
}
