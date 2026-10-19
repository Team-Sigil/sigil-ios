import CryptoKit
import DeviceCheck
import Foundation

/// Receipts taken in our own camera, signed by the device (gateway README, "Verified
/// in-app capture").
///
/// A photograph is only worth anything if it was taken by this app, on this phone, for
/// this request. App Attest proves the app and the device; the ticket ties it to the
/// request; the claim's hash ties it to the exact bytes uploaded. If any of that is
/// missing the gateway still stores the file — it just counts as a plain upload rather
/// than evidence.
enum VerifiedCapture {
    private static let keyAccount = "sigil.capture.key-id"
    private static let deviceAccount = "sigil.capture.device-id"

    /// False on the simulator and on anything without a Secure Enclave, where receipts
    /// upload as plain files instead.
    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// The enrolled device for this phone, attesting it first if needed.
    ///
    /// Enrolment happens once per install: a challenge from the gateway, a fresh App
    /// Attest key, and Apple's attestation over it. A device that fails (simulator,
    /// modified app, the wrong App Attest environment) gets `422 ATTESTATION_FAILED`.
    static func device(api: SigilAPI) async throws -> (deviceID: String, keyID: String) {
        if let deviceID = Keychain.readString(deviceAccount),
           let keyID = Keychain.readString(keyAccount) {
            return (deviceID, keyID)
        }
        let service = DCAppAttestService.shared
        guard service.isSupported else { throw CaptureError.unsupported }

        let challenge = try await api.captureChallenge().challenge
        let keyID = try await withCheckedThrowingContinuation { continuation in
            service.generateKey { key, error in
                if let key { continuation.resume(returning: key) }
                else { continuation.resume(throwing: error ?? CaptureError.unsupported) }
            }
        }
        // The gateway checks the attestation against `SHA-256(UTF-8 challenge)`.
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation = try await withCheckedThrowingContinuation { continuation in
            service.attestKey(keyID, clientDataHash: clientDataHash) { object, error in
                if let object { continuation.resume(returning: object) }
                else { continuation.resume(throwing: error ?? CaptureError.attestationFailed) }
            }
        }
        let device = try await api.enrolDevice(
            challenge: challenge,
            keyID: keyID,
            attestation: attestation.base64EncodedString()
        )
        Keychain.write(device.id, account: deviceAccount)
        Keychain.write(keyID, account: keyAccount)
        return (device.id, keyID)
    }

    /// The claim and its assertion for one photo, ready to upload beside the image.
    ///
    /// The signature covers the exact bytes of the claim text, and the claim covers the
    /// exact bytes of the image, so neither can be swapped for another afterwards.
    static func sign(
        image: Data, ticket: String, requestID: String, keyID: String
    ) async throws -> (claim: String, signature: String) {
        let digest = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let captured = ISO8601DateFormatter.capture.string(from: Date())
        // Built by hand so the bytes signed are exactly the bytes uploaded.
        let claim = """
        {"sha256":"\(digest)","nonce":"\(ticket)","request_id":"\(requestID)",\
        "captured_at":"\(captured)","device_key_id":"\(keyID)","app_version":"\(appVersion)"}
        """
        let clientDataHash = Data(SHA256.hash(data: Data(claim.utf8)))
        let assertion = try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.generateAssertion(
                keyID, clientDataHash: clientDataHash
            ) { assertion, error in
                if let assertion { continuation.resume(returning: assertion) }
                else { continuation.resume(throwing: error ?? CaptureError.assertionFailed) }
            }
        }
        return (claim, assertion.base64EncodedString())
    }

    /// Forgets this device's enrolment, so the next receipt attests again. Used when the
    /// gateway no longer recognises the key.
    static func forget() {
        Keychain.delete(keyAccount)
        Keychain.delete(deviceAccount)
    }
}

enum CaptureError: Error {
    case unsupported
    case attestationFailed
    case assertionFailed
    case noCamera
}

extension ISO8601DateFormatter {
    /// `captured_at` must carry a timezone, which the gateway checks against the ticket.
    static let capture: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
