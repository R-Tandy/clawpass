import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    var onCodeFound: (String) -> Void
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCodeFound = { code in
            onCodeFound(code)
        }
        controller.dismissAction = {
            presentationMode.wrappedValue.dismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    // Strong references to keep the pipeline alive
    private var captureSession: AVCaptureSession?
    private var metadataOutput: AVCaptureMetadataOutput?
    
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Start session ONLY after view is officially in the window hierarchy
        setupAndStartCamera()
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

    private func setupAndStartCamera() {
        SyncService.shared.log("[QRScanner] viewDidAppear: Starting Hardware Setup...")
        
        let session = AVCaptureSession()
        self.captureSession = session

        session.beginConfiguration()
        do {
            SyncService.shared.log("[QRScanner] Requesting camera device...")
            guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
                SyncService.shared.log("[QRScanner] FAIL: No camera available")
                session.commitConfiguration()
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                SyncService.shared.log("[QRScanner] FAIL: Cannot add input")
                session.commitConfiguration()
                return
            }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                self.metadataOutput = output
                
                // Use a high-priority background queue for the delegate
                let metadataQueue = DispatchQueue(label: "com.clawpass.qr.metadata", qos: .userInteractive)
                output.setMetadataObjectsDelegate(self, queue: metadataQueue)
                output.metadataObjectTypes = [.qr]
                SyncService.shared.log("[QRScanner] Metadata output configured and delegate bound")
            } else {
                SyncService.shared.log("[QRScanner] FAIL: Cannot add output")
                session.commitConfiguration()
                return
            }

            // Preview Layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.frame = self.view.frame
            previewLayer.videoGravity = .resizeAspectFill
            self.view.layer.insertSublayer(previewLayer, at: 0)
            
            self.statusLabel.text = "Scanning for connection QR..."
            
            // Run on a background thread to avoid freezing the UI, 
            // but ensure it's called after configuration is committed.
            DispatchQueue.global(qos: .userInteractive).async {
                session.startRunning()
                SyncService.shared.log("[QRScanner] session.startRunning() invoked. isRunning: \(session.isRunning)")
            }
        } catch {
            SyncService.shared.log("[QRScanner] CRITICAL error: \(error)")
            DispatchQueue.main.async {
                self.statusLabel.text = "Hardware Error"
            }
        }
        session.commitConfiguration()
        SyncService.shared.log("[QRScanner] Configuration committed.")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // ABSOLUTE PANIC LOG: If this fires once, the pipeline is alive.
        SyncService.shared.log("[QRScanner-DEBUG] Delegate fired. Objects: \(metadataObjects.count)")

        if metadataObjects.isEmpty {
            return 
        }

        DispatchQueue.main.async {
            self.statusIndicator.backgroundColor = .green
        }

        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let stringValue = metadataObject.stringValue {
            
            SyncService.shared.log("[QRScanner] SUCCESS: Found QR code: \(stringValue)")
            
            DispatchQueue.main.async {
                self.onCodeFound?(stringValue)
                self.dismissAction?()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}
