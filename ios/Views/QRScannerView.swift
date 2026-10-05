import SwiftUI
import AVFoundation
import Vision

// SINGLETON: Persistent manager to handle the Vision pipeline.
class CameraManager: NSObject {
    static let shared = CameraManager()
    
    var session: AVCaptureSession?
    var onCodeFound: ((String) -> Void)?
    
    private override init() {
        super.init()
    }
    
    func setupAndStart(previewLayer: AVCaptureVideoPreviewLayer) {
        SyncService.shared.log("[CameraManager] Initializing Vision-based session...")
        
        let session = AVCaptureSession()
        session.sessionPreset = .high
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

            // VISION PIPELINE: Use VideoDataOutput instead of MetadataOutput
            let videoOutput = AVCaptureVideoDataOutput()
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                
                // Use a dedicated queue for frame processing
                let processingQueue = DispatchQueue(label: "com.clawpass.vision.queue", qos: .userInteractive)
                videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
                SyncService.shared.log("[CameraManager] VideoDataOutput bound to Vision pipeline")
            } else {
                SyncService.shared.log("[CameraManager] FAIL: Cannot add video output")
                session.commitConfiguration()
                return
            }

            previewLayer.session = session
            
            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.frame = previewLayer.frame // Placeholder to avoid compiler warnings
                
                DispatchQueue.global(qos: .userInteractive).async {
                    session.startRunning()
                    SyncService.shared.log("[CameraManager] session.startRunning() called. isRunning: \(session.isRunning)")
                }
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
}

// Extend CameraManager to handle the frame analysis
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Log every few frames to prove the pipeline is flowing
        // (Actual logic would use a counter to avoid flooding logs)
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                SyncService.shared.log("[Vision] Request error: \(error)")
                return
            }
            
            guard let results = request.results as? [VNBarcodeObservation] else { return }
            
            if results.isEmpty {
                return 
            }
            
            if let firstResult = results.first, let payload = firstResult.payloadStringValue {
                SyncService.shared.log("[Vision] SUCCESS: Found QR code: \(payload)")
                DispatchQueue.main.async {
                    self.onCodeFound?(payload)
                }
            }
        }
        
        request.symbologies = [.qr]
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            SyncService.shared.log("[Vision] Handler error: \(error)")
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCodeFound: (String) -> Void
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        
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
        
        CameraManager.shared.setupAndStart(previewLayer: previewLayer)
    }

    private func setupUI() {
        statusLabel.text = "Initializing Camera..."
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.frame = CGRect(x: 20, y: view.// Fixed frame logic
            view.frame.height - 100, width: view.frame.width - 40, height: 40)
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
