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
        
        // Setup camera via coordinator
        context.coordinator.setupCamera(for: controller)
        
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: QRScannerView
        var captureSession: AVCaptureSession?
        
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
                
                let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                } else {
                    SyncService.shared.log("[QRScanner] FAIL: Session cannot add video input")
                    session.commitConfiguration()
                    return
                }

                let output = AVCaptureMetadataOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    // CRITICAL: Set the ViewController as the delegate, NOT the coordinator
                    output.setMetadataObjectsDelegate(controller, queue: DispatchQueue.main)
                    output.metadataObjectTypes = [.qr]
                } else {
                    SyncService.shared.log("[QRScanner] FAIL: Session cannot add metadata output")
                    session.commitConfiguration()
                    return
                }

                DispatchQueue.main.async {
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.frame = controller.view.frame
                    previewLayer.videoGravity = .resizeAspectFill
                    controller.view.layer.insertSublayer(previewLayer, at: 0)
                    
                    controller.statusLabel.text = "Scanning for connection QR..."
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        session.startRunning()
                        SyncService.shared.log("[QRScanner] session.startRunning() called. isRunning: \(session.isRunning)")
                    }
                }
            } catch {
                SyncService.shared.log("[QRScanner] CRITICAL: Hardware setup error: \(error)")
                DispatchQueue.main.async {
                    controller.statusLabel.text = "Hardware Error"
                }
            }
            session.commitConfiguration()
        }
    }
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
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

    func captureOutput(_ output: AVCaptureOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if metadataObjects.isEmpty {
            // Keep light red if nothing is found
            return 
        }

        // Light up green as soon as ANY object is detected
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
    }
}
