import AVFoundation
import SwiftUI
import UIKit

/// Reads a wallet address from a QR code — a wallet's "Receive" screen shows one.
///
/// A Solana address is 44 characters of base58, and one wrong character is money sent
/// somewhere nobody can reach. Scanning removes the chance to mistype it.
struct QRScannerSheet: View {
    var onFound: (String) -> Void

    /// Wallets encode the address in several shapes: on its own, as `solana:<address>`,
    /// or inside a longer URI. Rather than guess the format, every piece of the text is
    /// tried and the one that is a real 32-byte key wins.
    static func address(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Base58.isPubkey(trimmed) { return trimmed }
        let separators = CharacterSet(charactersIn: ":/?&=#,; \n\t")
        for token in trimmed.components(separatedBy: separators) where Base58.isPubkey(token) {
            return token
        }
        return nil
    }

    @Environment(\.dismiss) private var dismiss
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)
    /// Why the live camera isn't showing anything, when it isn't.
    @State private var cameraProblem: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch permission {
            case .authorized:
                QRScanner(onFound: { address in
                    onFound(address)
                    dismiss()
                }, onProblem: { cameraProblem = $0 })
                .ignoresSafeArea()
                guidance
            case .notDetermined:
                ProgressView().tint(.white)
            default:
                denied
            }
        }
        .task {
            guard permission == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            permission = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    /// Over the live camera: what to point it at, and a way out.
    private var guidance: some View {
        VStack {
            Text("Point at the QR code on their wallet's Receive screen")
                .font(Typo.body(15, .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.top, 24)

            Spacer()

            if let cameraProblem {
                // A black frame with no explanation reads as a broken app.
                VStack(spacing: 10) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(cameraProblem)
                        .font(Typo.body(15))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("You can also cancel and paste the address instead.")
                        .font(Typo.body(13))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 240, height: 240)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .font(Typo.body(16, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private var denied: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.8))
            Text("Sigil can't use the camera")
                .font(Typo.display(20))
                .foregroundStyle(.white)
            Text("Turn it on in Settings to scan a wallet's QR code, or paste the address instead.")
                .font(Typo.body(14))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            if let settings = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settings)
                    .font(Typo.body(15, .semibold))
                    .foregroundStyle(.white)
            }
            Button("Cancel") { dismiss() }
                .font(Typo.body(15))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 8)
        }
        .padding(32)
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    var onFound: (String) -> Void
    var onProblem: (String?) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onFound = onFound
        controller.onProblem = onProblem
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onFound: ((String) -> Void)?
        var onProblem: ((String?) -> Void)?
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "casa.iden.sigil.scanner")
        private var preview: AVCaptureVideoPreviewLayer?
        private var rotation: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?
        private var observers: [NSObjectProtocol] = []
        private var found = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video) else {
                report("This device has no camera Sigil can use.")
                return
            }

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
            followRotation(of: device, preview: layer)
            observeInterruptions()

            // Configuring and starting a session both block, so neither runs on the main
            // thread; a stalled main thread is one more way to end up with a black frame.
            queue.async { [weak self] in self?.configure(device) }
        }

        private func configure(_ device: AVCaptureDevice) {
            session.beginConfiguration()
            // On iPad, iOS cuts a capture session off whenever the app shares the screen
            // (Split View, Slide Over, Stage Manager) unless it opts in. The receipt camera
            // is the system's picker, which does this itself; this session has to ask.
            if session.isMultitaskingCameraAccessSupported {
                session.isMultitaskingCameraAccessEnabled = true
            }
            guard let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                report("The camera couldn't be started.")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                report("The camera can't read QR codes on this device.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            // Set after adding to the session, or the type isn't available yet.
            output.metadataObjectTypes = [.qr]
            session.commitConfiguration()
            session.startRunning()
        }

        /// Keeps the preview upright as the iPad turns; without it the picture is
        /// sideways in landscape.
        private func followRotation(of device: AVCaptureDevice, preview: AVCaptureVideoPreviewLayer) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
            rotation = coordinator
            let apply = { [weak preview] (angle: CGFloat) in
                guard let connection = preview?.connection,
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
            apply(coordinator.videoRotationAngleForHorizonLevelPreview)
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview, options: [.new]
            ) { _, change in
                guard let angle = change.newValue else { return }
                DispatchQueue.main.async { apply(angle) }
            }
        }

        private func observeInterruptions() {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                               object: session, queue: .main) { [weak self] note in
                let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
                let reason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
                self?.report(Self.message(for: reason))
            })
            observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                               object: session, queue: .main) { [weak self] _ in
                self?.report(nil)
            })
            observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                               object: session, queue: .main) { [weak self] _ in
                self?.report("The camera stopped. Close this and try again.")
                self?.queue.async { [weak self] in self?.session.startRunning() }
            })
        }

        private static func message(for reason: AVCaptureSession.InterruptionReason?) -> String {
            switch reason {
            case .videoDeviceNotAvailableWithMultipleForegroundApps:
                "The camera is paused while another app shares the screen. Make Sigil full screen to scan."
            case .videoDeviceInUseByAnotherClient:
                "Another app is using the camera. Close it, then come back."
            case .videoDeviceNotAvailableDueToSystemPressure:
                "The camera is paused because the iPad is too warm. Try again in a moment."
            default:
                "The camera is paused. Close this and try again."
            }
        }

        private func report(_ problem: String?) {
            DispatchQueue.main.async { [weak self] in self?.onProblem?(problem) }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            queue.async { [session] in
                // Before configuration finishes there are no inputs; `configure` starts it.
                if !session.isRunning, !session.inputs.isEmpty { session.startRunning() }
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            queue.async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput objects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !found else { return }
            for object in objects {
                guard let code = object as? AVMetadataMachineReadableCodeObject,
                      let text = code.stringValue,
                      let address = Self.address(in: text) else { continue }
                found = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onFound?(address)
                return
            }
        }

        static func address(in text: String) -> String? {
            QRScannerSheet.address(in: text)
        }
    }
}
