import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    var onCodeFound: (String) -> Void
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCodeFound = onCodeFound
        controller.dismissAction = {
            context.coordinator.dismiss()
        }
        
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
            SyncService.shared.log("[QRScanner] Beginning setupCamera process...")
            let session = AVCaptureSession()
            self.captureSession = session

            session.beginConfiguration()
            do {
                SyncService.shared.log("[QRScanner] Requesting default video device...")
                guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
                    SyncService.shared.log("[QRScanner] FAIL: No camera available")
                    session.commitConfiguration()
                    return
                }
                SyncService.shared.log("[QRScanner] Camera device found: \(videoCaptureDevice.localizedName)")
                
                SyncService.shared.log("[QRScanner] Creating video input...")
                let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                    SyncService.shared.log("[QRScanner] SUCCESS: Video input added")
                } else {
                    SyncService.shared.log("[QRScanner] FAIL: Session cannot add video input")
                    session.commitConfiguration()
                    return
                }

                SyncService.shared.log("[QRScanner] Creating metadata output...")
                let output = AVCaptureMetadataOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.metadataObjectTypes = [.qr]
                    output.setMetadataObjectsDelegate(self, queue: metadataQueue)
                    self.metadataOutput = output
                    SyncService.shared.log("[QRScanner] SUCCESS: Metadata output added and delegate set")
                } else {
                    SyncService.shared.log("[QRScanner] FAIL: Session cannot add metadata output")
                    session.commitConfiguration()
                    return
                }

                DispatchQueue.main.async {
                    SyncService.shared.log("[QRScanner] Configuring preview layer on main thread...")
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.frame = controller.view.frame
                    previewLayer.videoGravity = .resizeAspectFill
                    controller.view.layer.insertSublayer(previewLayer, at: 0)
                    
                    self.metadataOutput?.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
                    controller.statusLabel.text = "Scanning for connection QR..."
                    SyncService.shared.log("[QRScanner] Preview layer and rectOfInterest configured")
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        SyncService.shared.log("[QRScanner] Attempting session.startRunning()...")
                        session.startRunning()
                        SyncService.shared.log("[QRScanner] session.startRunning() called. Checking if actually running: \(session.isRunning)")
                    }
                }
            } catch {
                SyncService.shared.log("[QRScanner] CRITICAL: Hardware setup error: \(error)")
                DispatchQueue.main.async {
                    controller.statusLabel.text = "Hardware Error"
                }
            }
            session.commitConfiguration()
            SyncService.shared.log("[QRScanner] Configuration committed.")
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
        
        func dismiss() {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

class ScannerViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var onCodeFound: ((String) -> Void)?
    var dismissAction: (() -> Void)?
    
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}