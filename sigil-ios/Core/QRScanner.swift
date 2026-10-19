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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch permission {
            case .authorized:
                QRScanner { address in
                    onFound(address)
                    dismiss()
                }
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

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                .frame(width: 240, height: 240)

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

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onFound = onFound
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onFound: ((String) -> Void)?
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "casa.iden.sigil.scanner")
        private var preview: AVCaptureVideoPreviewLayer?
        private var found = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            // Set after adding to the session, or the type isn't available yet.
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            // startRunning blocks, so it never belongs on the main thread.
            queue.async { [session] in
                if !session.isRunning { session.startRunning() }
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
