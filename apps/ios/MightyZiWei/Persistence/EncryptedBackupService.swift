import CryptoKit
import Foundation

struct BackupRecoveryKey: Equatable, Sendable {
    static let byteCount = 32

    let rawRepresentation: Data

    init() {
        let key = SymmetricKey(size: .bits256)
        self.rawRepresentation = key.withUnsafeBytes { Data($0) }
    }

    init(rawRepresentation: Data) throws {
        guard rawRepresentation.count == Self.byteCount else {
            throw BackupError.invalidRecoveryKey
        }
        self.rawRepresentation = rawRepresentation
    }

    init(encoded: String) throws {
        guard let data = Data(base64Encoded: encoded) else {
            throw BackupError.invalidRecoveryKey
        }
        try self.init(rawRepresentation: data)
    }

    var encoded: String {
        rawRepresentation.base64EncodedString()
    }

    fileprivate var symmetricKey: SymmetricKey {
        SymmetricKey(data: rawRepresentation)
    }
}

struct EncryptedBackup: Equatable, Sendable {
    let data: Data
    let recoveryKey: BackupRecoveryKey
}

struct EncryptedBackupEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let algorithm = "AES-256-GCM"

    let schemaVersion: Int
    let algorithm: String
    let sealedPayload: Data
}

enum BackupError: Error, Equatable {
    case inputTooLarge(maximumBytes: Int)
    case malformedBackup
    case unsupportedEnvelopeSchema(Int)
    case unsupportedPayloadSchema(Int)
    case unsupportedAlgorithm(String)
    case unsupportedChartSchema(chartID: UUID, schemaVersion: Int)
    case invalidChartData(UUID)
    case invalidRecoveryKey
    case authenticationFailed
    case duplicateChartID(UUID)
    case duplicateInsightID(UUID)
    case missingInsightChart(insightID: UUID, chartID: UUID)
    case invalidInsightKind(String)
    case invalidInsightMarker(String)
    case invalidInsightLocation
    case invalidEvidenceFactID
}

extension BackupError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .inputTooLarge(maximumBytes):
            "備份資料超過 \(maximumBytes) 位元組限制。"
        case .malformedBackup:
            "備份檔格式無法辨識。"
        case let .unsupportedEnvelopeSchema(version):
            "不支援備份封裝版本 \(version)。"
        case let .unsupportedPayloadSchema(version):
            "不支援備份資料版本 \(version)。"
        case let .unsupportedAlgorithm(algorithm):
            "不支援備份加密演算法 \(algorithm)。"
        case let .unsupportedChartSchema(_, version):
            "不支援命盤資料版本 \(version)。"
        case .invalidChartData:
            "備份包含無法重新計算的出生資料。"
        case .invalidRecoveryKey:
            "復原金鑰必須是 256-bit 金鑰。"
        case .authenticationFailed:
            "復原金鑰不正確，或備份資料已遭竄改。"
        case .duplicateChartID:
            "備份包含重複的命盤識別碼。"
        case .duplicateInsightID:
            "備份包含重複的 insight 識別碼。"
        case .missingInsightChart:
            "收藏或筆記引用了備份中不存在的命盤。"
        case .invalidInsightKind:
            "備份包含不支援的收藏或筆記類型。"
        case .invalidInsightMarker:
            "備份包含不支援的自我觀察標記。"
        case .invalidInsightLocation:
            "備份中的收藏或筆記缺少來源位置。"
        case .invalidEvidenceFactID:
            "備份中的收藏包含無效命盤依據。"
        }
    }
}

enum EncryptedBackupService {
    static let maximumInputSize = 10 * 1_024 * 1_024
    static let authenticatedData = Data("MightyZiWei|BackupEnvelope|1|AES-256-GCM".utf8)

    static func makeBackup(
        savedCharts: [SavedChart],
        insights: [BackupInsightDTO] = []
    ) throws -> EncryptedBackup {
        try encrypt(BackupPayload(savedCharts: savedCharts, insights: insights))
    }

    static func makeBackup(
        savedCharts: [SavedChart],
        savedInsights: [SavedInsight]
    ) throws -> EncryptedBackup {
        try encrypt(BackupPayload(savedCharts: savedCharts, savedInsights: savedInsights))
    }

    static func encrypt(_ payload: BackupPayload) throws -> EncryptedBackup {
        try payload.validate()
        let payloadData = try BackupJSONCoding.encoder().encode(payload)
        try validateSize(payloadData)

        let recoveryKey = BackupRecoveryKey()
        let sealedBox = try AES.GCM.seal(
            payloadData,
            using: recoveryKey.symmetricKey,
            authenticating: authenticatedData
        )
        guard let combined = sealedBox.combined else {
            throw BackupError.malformedBackup
        }

        let envelope = EncryptedBackupEnvelope(
            schemaVersion: EncryptedBackupEnvelope.currentSchemaVersion,
            algorithm: EncryptedBackupEnvelope.algorithm,
            sealedPayload: combined
        )
        let backupData = try BackupJSONCoding.encoder().encode(envelope)
        try validateSize(backupData)
        return EncryptedBackup(data: backupData, recoveryKey: recoveryKey)
    }

    static func restore(
        from backupData: Data,
        recoveryKey: BackupRecoveryKey
    ) throws -> BackupPayload {
        try validateSize(backupData)

        let envelope: EncryptedBackupEnvelope
        do {
            envelope = try BackupJSONCoding.decoder().decode(
                EncryptedBackupEnvelope.self,
                from: backupData
            )
        } catch {
            throw BackupError.malformedBackup
        }

        guard envelope.schemaVersion == EncryptedBackupEnvelope.currentSchemaVersion else {
            throw BackupError.unsupportedEnvelopeSchema(envelope.schemaVersion)
        }
        guard envelope.algorithm == EncryptedBackupEnvelope.algorithm else {
            throw BackupError.unsupportedAlgorithm(envelope.algorithm)
        }

        let payloadData: Data
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: envelope.sealedPayload)
            payloadData = try AES.GCM.open(
                sealedBox,
                using: recoveryKey.symmetricKey,
                authenticating: authenticatedData
            )
        } catch {
            throw BackupError.authenticationFailed
        }
        try validateSize(payloadData)

        let payload: BackupPayload
        do {
            payload = try BackupJSONCoding.decoder().decode(BackupPayload.self, from: payloadData)
        } catch {
            throw BackupError.malformedBackup
        }
        try payload.validate()
        return payload
    }

    static func restore(from backupData: Data, encodedRecoveryKey: String) throws -> BackupPayload {
        try restore(
            from: backupData,
            recoveryKey: BackupRecoveryKey(encoded: encodedRecoveryKey)
        )
    }

    private static func validateSize(_ data: Data) throws {
        guard data.count <= maximumInputSize else {
            throw BackupError.inputTooLarge(maximumBytes: maximumInputSize)
        }
    }
}
