import Foundation

/// A legacy Solana transaction, built by hand.
///
/// Sigil only ever builds one kind: the guardian delegating aUSD from their reservoir to
/// the agent wallet (`ApproveChecked`), and taking it back (`Revoke`). The app never signs
/// it — Phantom does — so this only has to produce the exact bytes the wallet will show
/// and the chain will accept. The byte layout is checked against `solders`.
/// The devnet facts the app has to know to build a delegation.
///
/// The agent wallet is the delegate every approval names. The gateway knows it as
/// `AGENT_WALLET_PUBKEY` but exposes it on no route, so it lives here.
enum Chain {
    static let agentWallet = "9ZtfQjn6h61LnVqd7EquSQZDMjdApEd26cJvDGxBqNh9"
    static let decimals: UInt8 = 6

    static func explorer(transaction signature: String) -> URL? {
        URL(string: "https://explorer.solana.com/tx/\(signature)?cluster=devnet")
    }
}

enum SolanaTransaction {
    static let tokenProgram = TokenAccount.tokenProgram

    /// SPL Token instruction 13: delegate `amount` of `mint` from `reservoir`.
    ///
    /// "Checked" because it carries the mint and its decimals, so the wallet can show a
    /// real figure and the program refuses a mismatch — the unchecked `Approve` (4) can be
    /// shown as a meaningless raw number.
    static func approveChecked(
        reservoir: String,
        mint: String,
        delegate: String,
        owner: String,
        amount: UInt64,
        decimals: UInt8,
        blockhash: String
    ) -> String? {
        guard let reservoirKey = Base58.decode(reservoir),
              let mintKey = Base58.decode(mint),
              let delegateKey = Base58.decode(delegate),
              let ownerKey = Base58.decode(owner) else { return nil }

        // tag + amount (u64 little-endian) + decimals: ten bytes.
        var data: [UInt8] = [13]
        for shift in stride(from: 0, through: 56, by: 8) {
            data.append(UInt8(truncatingIfNeeded: amount >> UInt64(shift)))
        }
        data.append(decimals)

        return transaction(
            feePayer: ownerKey,
            blockhash: blockhash,
            instruction: Instruction(
                program: tokenProgram,
                accounts: [
                    Account(key: reservoirKey, isSigner: false, isWritable: true),
                    Account(key: mintKey, isSigner: false, isWritable: false),
                    Account(key: delegateKey, isSigner: false, isWritable: false),
                    Account(key: ownerKey, isSigner: true, isWritable: false),
                ],
                data: data
            )
        )
    }

    /// SPL Token instruction 5: hands the delegation back, whatever is left of it.
    static func revoke(reservoir: String, owner: String, blockhash: String) -> String? {
        guard let reservoirKey = Base58.decode(reservoir),
              let ownerKey = Base58.decode(owner) else { return nil }
        return transaction(
            feePayer: ownerKey,
            blockhash: blockhash,
            instruction: Instruction(
                program: tokenProgram,
                accounts: [
                    Account(key: reservoirKey, isSigner: false, isWritable: true),
                    Account(key: ownerKey, isSigner: true, isWritable: false),
                ],
                data: [5]
            )
        )
    }

    // MARK: Building

    struct Account {
        let key: [UInt8]
        let isSigner: Bool
        let isWritable: Bool
    }

    struct Instruction {
        let program: String
        let accounts: [Account]
        let data: [UInt8]
    }

    /// The unsigned transaction, base58, as a wallet expects to receive it: an empty
    /// signature slot followed by the message.
    private static func transaction(
        feePayer: [UInt8], blockhash: String, instruction: Instruction
    ) -> String? {
        guard let message = message(
            feePayer: feePayer, blockhash: blockhash, instruction: instruction
        ) else { return nil }
        // One signature is required (the fee payer's); the wallet fills it in.
        var out = compactLength(1)
        out.append(contentsOf: [UInt8](repeating: 0, count: 64))
        out.append(contentsOf: message)
        return Base58.encode(out)
    }

    private static func message(
        feePayer: [UInt8], blockhash: String, instruction: Instruction
    ) -> [UInt8]? {
        guard let programKey = Base58.decode(instruction.program),
              let blockhashBytes = Base58.decode(blockhash),
              blockhashBytes.count == 32 else { return nil }

        // The fee payer is always first, always a writable signer. Everything else keeps
        // the order it was named in, with duplicates merged so a key that is both signer
        // and writable stays both.
        // The program being invoked is registered before the accounts it is given, which
        // is what decides the order of the read-only block — get it the other way round
        // and every account index in the instruction is off.
        var accounts: [Account] = [Account(key: feePayer, isSigner: true, isWritable: true)]
        for account in [Account(key: programKey, isSigner: false, isWritable: false)]
            + instruction.accounts {
            if let index = accounts.firstIndex(where: { $0.key == account.key }) {
                accounts[index] = Account(
                    key: account.key,
                    isSigner: accounts[index].isSigner || account.isSigner,
                    isWritable: accounts[index].isWritable || account.isWritable
                )
            } else {
                accounts.append(account)
            }
        }

        // Ordered as the runtime expects: writable signers, read-only signers, writable
        // others, read-only others. The fee payer is already first and stays there.
        let ordered = accounts.enumerated().sorted { left, right in
            let (a, b) = (left.element, right.element)
            if a.isSigner != b.isSigner { return a.isSigner }
            if a.isWritable != b.isWritable { return a.isWritable }
            return left.offset < right.offset
        }.map(\.element)

        let signers = ordered.filter(\.isSigner)
        let readonlySigners = signers.filter { !$0.isWritable }.count
        let readonlyOthers = ordered.filter { !$0.isSigner && !$0.isWritable }.count

        var out: [UInt8] = [
            UInt8(signers.count), UInt8(readonlySigners), UInt8(readonlyOthers),
        ]
        out.append(contentsOf: compactLength(ordered.count))
        for account in ordered { out.append(contentsOf: account.key) }
        out.append(contentsOf: blockhashBytes)

        out.append(contentsOf: compactLength(1))
        guard let programIndex = ordered.firstIndex(where: { $0.key == programKey })
        else { return nil }
        out.append(UInt8(programIndex))
        out.append(contentsOf: compactLength(instruction.accounts.count))
        for account in instruction.accounts {
            guard let index = ordered.firstIndex(where: { $0.key == account.key })
            else { return nil }
            out.append(UInt8(index))
        }
        out.append(contentsOf: compactLength(instruction.data.count))
        out.append(contentsOf: instruction.data)
        return out
    }

    /// Solana's compact-u16: seven bits per byte, high bit meaning "more follows".
    private static func compactLength(_ value: Int) -> [UInt8] {
        var remaining = value
        var out: [UInt8] = []
        while remaining >= 0x80 {
            out.append(UInt8(remaining & 0x7F) | 0x80)
            remaining >>= 7
        }
        out.append(UInt8(remaining))
        return out
    }
}
