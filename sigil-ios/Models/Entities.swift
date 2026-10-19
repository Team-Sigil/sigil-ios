import SwiftUI

enum Role: String {
    case guardian, dependent
}

/// Signed-in state shared by the whole app.
///
/// A guardian may support several dependents, each in its own family. Guardian calls
/// about one dependent carry that family in the `X-Family-Id` header, so the selected
/// family is session state, not a screen's local state.
@MainActor
@Observable
final class AppSession {
    var role: Role?

    /// `family_ids` from sign-in, oldest first. Empty for a guardian means onboarding.
    var familyIDs: [String] = []

    /// The family every guardian request is about. Nil until one is chosen.
    var selectedFamilyID: String?

    /// The signed-in wallet address, base58.
    var wallet: String?

    /// What the gateway calls them, when it knows.
    var displayName: String?

    /// True while a stored session is being checked, so the app doesn't flash onboarding
    /// at someone who is already signed in.
    var restoring = false

    /// Set when sign-in itself failed, in the gateway's words.
    var signInProblem: String?

    private var token: String?

    /// Freeze is per family (SEC-17): "freeze everyone" is one signature each. Mirrors
    /// `families.frozen` from the gateway; the Store refreshes it on every load.
    private var frozenFamilies: Set<String> = []

    private static let tokenAccount = "sigil.session.token"
    private static let roleAccount = "sigil.session.role"

    var signedIn: Bool { token != nil && role != nil }
    var needsOnboarding: Bool { role == .guardian && familyIDs.isEmpty }
    var hasSeveralDependents: Bool { familyIDs.count > 1 }

    /// The wallet. Phantom on a device; the in-app key only with `-localWallet`, which is
    /// how the simulator (where Phantom cannot be installed) is still usable.
    var signer: WalletService {
        LocalWallet.isEnabled ? LocalWallet(role: debugRole) : PhantomWallet()
    }

    /// Only meaningful for `-localWallet`: which of the two test keys to sign with.
    private var debugRole: Role = .guardian

    /// The API, already carrying the session and the selected family.
    var api: SigilAPI {
        var api = SigilAPI()
        api.token = token
        // A dependent has one family and never needs the header; a guardian with one
        // family may leave it out, but sending it is always correct.
        api.familyID = role == .dependent ? nil : selectedFamilyID
        return api
    }

    /// The API scoped to one specific family, for the guardian's per-dependent reads.
    func api(for familyID: String) -> SigilAPI {
        var api = self.api
        api.familyID = familyID
        return api
    }

    func isFrozen(_ familyID: String) -> Bool {
        frozenFamilies.contains(familyID)
    }

    var frozenCount: Int { frozenFamilies.count }

    /// Applied from the gateway's families, which own this state.
    func applyFrozen(_ families: [FamilyDTO]) {
        frozenFamilies = Set(families.filter(\.frozen).map(\.id))
    }

    /// Only for the optimistic flip right after a signed freeze; the next load confirms it.
    func setFrozen(_ frozen: Bool, familyID: String) {
        if frozen {
            frozenFamilies.insert(familyID)
        } else {
            frozenFamilies.remove(familyID)
        }
    }

    // MARK: Sign-in

    /// Signs in with the wallet: connect, a nonce, the gateway's exact text signed, a token.
    ///
    /// There is no password anywhere in Sigil — proving the wallet *is* the sign-in
    /// (SEC-09). The role is not chosen here either: the gateway decides it from the
    /// wallet, and a wallet registered as someone's dependent is a dependent. The address
    /// comes from the wallet itself, so the app can never be pointed at an account the
    /// person doesn't control.
    func signIn() async {
        signInProblem = nil
        // Which step failed, so an error says whether Phantom or the gateway refused.
        var step = "Connecting to Phantom"
        do {
            let wallet = signer
            // A saved Phantom session may have been revoked in Phantom (4100), or belong to
            // another account; signing in is the moment to start clean. The local test
            // wallet is left alone: disconnecting it forgets its key.
            if wallet is PhantomWallet { wallet.disconnect() }
            let address = try await wallet.connect()
            let api = SigilAPI()
            step = "Getting the sign-in message"
            let challenge = try await api.nonce(wallet: address, purpose: "login")
            guard let message = challenge.message else {
                signInProblem = "The gateway didn't send a sign-in message."
                return
            }
            // Signed byte for byte: the gateway rebuilds this text and compares.
            step = "Signing in Phantom"
            let signature = try await wallet.sign(message)
            step = "Checking the signature"
            let session = try await api.verify(
                wallet: address, message: message, signature: signature
            )
            adopt(session, wallet: address)
        } catch PhantomError.cancelled {
            // Tapping Cancel in Phantom is an answer, not a failure to report.
        } catch let error as PhantomError {
            signInProblem = "\(step) failed. \(error.readable)"
        } catch let error as APIError {
            signInProblem = "\(step) failed. \(error.readable)"
        } catch {
            signInProblem = "\(step) failed. Couldn't reach the gateway."
        }
    }

    /// Only for `-localWallet`: picks which test key signs, then signs in as usual.
    func signIn(as requested: Role) async {
        debugRole = requested
        await signIn()
    }

    /// Picks up a session the gateway just issued.
    func adopt(_ session: Session, wallet address: String) {
        token = session.token
        wallet = address
        familyIDs = session.familyIds
        selectedFamilyID = session.familyId ?? session.familyIds.first
        Keychain.write(session.token, account: Self.tokenAccount)
        Keychain.write(session.role, account: Self.roleAccount)
        withAnimation(.easeInOut(duration: 0.3)) {
            role = Role(rawValue: session.role)
        }
    }

    /// Registering a dependent returns a fresh token and a new family.
    func adopt(_ registered: RegisteredFamilyDTO) {
        token = registered.token
        Keychain.write(registered.token, account: Self.tokenAccount)
        if !familyIDs.contains(registered.family.id) {
            familyIDs.append(registered.family.id)
        }
        if selectedFamilyID == nil {
            selectedFamilyID = registered.family.id
        }
    }

    /// Takes the gateway's word for who this session belongs to, including the role,
    /// which can change when a guardian registers this wallet as their dependent.
    func adopt(_ me: Me) {
        wallet = me.wallet
        displayName = me.displayName
        familyIDs = me.familyIds
        if selectedFamilyID == nil || !me.familyIds.contains(selectedFamilyID ?? "") {
            selectedFamilyID = me.familyId ?? me.familyIds.first
        }
        if let role = Role(rawValue: me.role), role != self.role {
            withAnimation(.easeInOut(duration: 0.3)) { self.role = role }
        }
    }

    /// Restores a stored session on launch, by asking the gateway who it belongs to.
    /// A token that has expired (12 h at most) simply means signing in again.
    func restore() async {
        guard let stored = Keychain.readString(Self.tokenAccount),
              let storedRole = Keychain.readString(Self.roleAccount) else { return }
        restoring = true
        defer { restoring = false }
        token = stored
        do {
            let me = try await api.me()
            role = Role(rawValue: me.role) ?? Role(rawValue: storedRole)
            adopt(me)
        } catch {
            token = nil
            Keychain.delete(Self.tokenAccount)
            Keychain.delete(Self.roleAccount)
        }
    }

    func signOut() {
        Keychain.delete(Self.tokenAccount)
        Keychain.delete(Self.roleAccount)
        // Disconnecting is also how you switch to another Phantom account: the next
        // sign-in connects again and takes whichever wallet is active then.
        signer.disconnect()
        token = nil
        wallet = nil
        displayName = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            role = nil
            familyIDs = []
            selectedFamilyID = nil
            frozenFamilies = []
        }
    }
}

/// The signed-in guardian, as their own screens show them.
///
/// The gateway has no route that sets a display name and none that tells a dependent their
/// guardian's name, so the name falls back to the start of the wallet address rather than
/// inventing one.
struct Guardian: Sendable {
    let name: String
    /// What the dependents call them, used in dependent-facing copy.
    let shortName: String
    let initials: String
    let wallet: String

    init(wallet: String, displayName: String? = nil) {
        let fallback = String(wallet.prefix(4))
        name = displayName ?? fallback
        shortName = displayName ?? "your guardian"
        initials = Self.initials(of: displayName ?? fallback)
        self.wallet = wallet
    }

    static func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

struct Dependent: Identifiable, Sendable {
    let id: String
    /// Each dependent is their own family, and that id goes in `X-Family-Id`.
    let familyID: String
    let name: String
    let initials: String
    /// The one address their allowance can reach, registered by guardian
    /// signature (gateway "Guardian signatures").
    let tokenAccount: String
    let avatarBackground: Color
    let avatarForeground: Color
    let sentThisMonth: Units
    let requestsThisMonth: Int
    let awaitingGuardian: Int
}

/// `GET /budget`. A budget week runs Monday to Monday in the family's timezone.
struct Budget: Sendable {
    let spent: Units
    /// Cleared and reserved, but not yet confirmed on chain.
    let reserved: Units
    let weeklyCap: Units
    let remaining: Units
    /// `null` when the crypto layer cannot be read — the app must show that it is
    /// unknown rather than invent a number.
    let delegatedRemaining: Units?
    let resetText: String

    var fraction: Double { (spent + reserved).fraction(of: weeklyCap) }
}

/// One request as a list row. Built from the request plus its latest decision.
struct ActivityItem: Identifiable, Sendable {
    let id: String
    let outcome: Outcome
    let title: String
    let dependentID: String
    /// What was asked for.
    let amount: Units
    /// What actually moved, from `decision.amount_sent`.
    let amountSent: Units
    let category: Category
    /// `decision.reply_to_dependent` — the agent's own words.
    let reply: String
    /// `decision.summary_for_guardian`, which dependents must never see.
    let summaryForGuardian: String?
    let emergencyClaimed: Bool
    let txSignature: String?
    let time: String
    /// When it happened, for grouping the activity list by day.
    let at: Date?

    init(
        id: String = UUID().uuidString,
        outcome: Outcome,
        title: String,
        dependentID: String,
        amount: Units,
        amountSent: Units = .zero,
        category: Category,
        reply: String,
        summaryForGuardian: String? = nil,
        emergencyClaimed: Bool = false,
        time: String,
        txSignature: String? = nil,
        at: Date? = nil
    ) {
        self.id = id
        self.outcome = outcome
        self.title = title
        self.dependentID = dependentID
        self.amount = amount
        self.amountSent = amountSent
        self.category = category
        self.reply = reply
        self.summaryForGuardian = summaryForGuardian
        self.emergencyClaimed = emergencyClaimed
        self.txSignature = txSignature
        self.time = time
        self.at = at
    }
}

struct ActivityGroup: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let items: [ActivityItem]
}

/// `QuestionView`. Answering takes a wallet signature; a claim in chat never counts.
struct GuardianQuestion: Identifiable, Sendable {
    let id: String
    let requestID: String?
    let dependentID: String
    let title: String
    let question: String
    let amount: Units
    let category: Category
    let recommendation: Recommendation
    let recommendedAmount: Units?
    let urgency: Urgency
    /// The maker's case.
    let agentView: String
    /// The checker's case. Absent when no review was required.
    let auditorView: String?
    let askedAgo: String
    let emergencyClaimed: Bool
    let proofs: [Proof]
    /// When it was asked, for ordering. `askedAgo` is for reading, not sorting.
    var at: Date?
}

/// A receipt owed for money already sent (`GET /proof-obligations`). While one is open
/// the dependent cannot ask for more: `POST /requests` answers `409 PROOF_OUTSTANDING`.
struct ProofObligation: Identifiable, Sendable {
    let id: String
    let requestID: String
    let transferID: String
    let amount: Units
    let title: String
    let sentAgo: String
}

struct Notification: Identifiable, Sendable {
    let id: String
    /// Nil when the notification is about the guardian as a whole, such as the
    /// shared reservoir, rather than one dependent.
    let familyID: String?
    let message: String
    let time: String
    let isRead: Bool
}

struct WeeklySummary: Identifiable, Sendable {
    let id: String
    let weekOf: String
    let body: String
    let sent: Units
    let requests: Int
    let flagged: Int
}

/// One link in the append-only, hash-chained log. The gateway re-verifies the whole
/// chain on every read and returns `chain_valid` with it.
struct AuditLogEntry: Identifiable, Sendable {
    let id: Int
    let event: String
    let detail: String
    let time: String
    let hashPrefix: String
}

extension Array {
    /// Bounds-checked access, for reading launch arguments in pairs.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
