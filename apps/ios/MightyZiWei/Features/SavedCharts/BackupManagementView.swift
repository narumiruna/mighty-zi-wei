import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.malformedBackup
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupRestoreWarning {
    static let message =
        "還原會以備份取代相同識別碼命盤的整本筆記與收藏。本機較新的內容若不在備份中，也會永久刪除。"
}

struct BackupManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedChart.updatedAt, order: .reverse) private var charts: [SavedChart]
    @Query private var insights: [SavedInsight]

    @State private var exportDocument: BackupDocument?
    @State private var exportRecoveryKey = ""
    @State private var importRecoveryKey = ""
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var importedData: Data?
    @State private var importedFilename: String?
    @State private var isExporting = false
    @State private var isRestoring = false
    @State private var showsRestoreConfirmation = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("備份包含已儲存命盤、私人筆記與收藏；不包含 API key、endpoint、AI 對話或衍生命盤快取。")
                    .font(.footnote)
            }

            Section("建立加密備份") {
                LabeledContent("命盤", value: "\(charts.count) 張")
                LabeledContent("筆記與收藏", value: "\(insights.count) 則")
                Button {
                    prepareExport()
                } label: {
                    if isExporting {
                        ProgressView("正在建立加密備份…")
                    } else {
                        Label("建立 AES-GCM 加密備份", systemImage: "lock.doc")
                    }
                }
                .disabled(charts.isEmpty || isExporting)
                .accessibilityIdentifier("backup.export")

                if !exportRecoveryKey.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("復原金鑰只顯示於本次畫面")
                            .font(.headline)
                        Text(exportRecoveryKey)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("backup.recoveryKey")
                        Text("請將金鑰與備份檔分開保存。遺失金鑰後無法還原，App 也無法代為找回。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("還原備份") {
                Button {
                    showsImporter = true
                } label: {
                    Label("選擇備份檔", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("backup.import")

                if let importedFilename {
                    LabeledContent("已選擇", value: importedFilename)
                    TextField("貼上復原金鑰", text: $importRecoveryKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                        .accessibilityIdentifier("backup.importKey")
                    Button {
                        showsRestoreConfirmation = true
                    } label: {
                        if isRestoring {
                            ProgressView("正在驗證備份…")
                        } else {
                            Text("解密並還原")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isRestoring
                            || importRecoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityIdentifier("backup.restore")
                    Text(BackupRestoreWarning.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("加密備份與還原")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .data,
            defaultFilename: "很牛的紫微斗數備份.mzwbackup"
        ) { result in
            if case .failure = result {
                errorMessage = "備份檔未儲存；你可以重新建立備份。"
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            selectImport(result)
        }
        .confirmationDialog(
            "還原並取代整本內容？",
            isPresented: $showsRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("還原並取代", role: .destructive) {
                restore()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(BackupRestoreWarning.message)
        }
        .alert("備份操作未完成", isPresented: errorIsPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func prepareExport() {
        guard !isExporting else { return }
        do {
            let chartIDs = Set(charts.map(\.id))
            let includedInsights = insights.filter { chartIDs.contains($0.chartID) }
            let snapshot = try BackupExportSnapshot(
                savedCharts: charts,
                savedInsights: includedInsights
            )
            isExporting = true

            Task {
                do {
                    let backup = try await Task.detached(priority: .userInitiated) {
                        try EncryptedBackupService.makeBackup(snapshot)
                    }.value
                    exportDocument = BackupDocument(data: backup.data)
                    exportRecoveryKey = backup.recoveryKey.encoded
                    statusMessage = nil
                    showsExporter = true
                } catch {
                    errorMessage = safeMessage(for: error)
                }
                isExporting = false
            }
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    private func selectImport(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first
            guard let url else { throw BackupError.malformedBackup }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values.fileSize,
               fileSize > EncryptedBackupService.maximumInputSize {
                throw BackupError.inputTooLarge(
                    maximumBytes: EncryptedBackupService.maximumInputSize
                )
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(
                upToCount: EncryptedBackupService.maximumInputSize + 1
            ) ?? Data()
            if data.count > EncryptedBackupService.maximumInputSize {
                throw BackupError.inputTooLarge(
                    maximumBytes: EncryptedBackupService.maximumInputSize
                )
            }
            importedData = data
            importedFilename = url.lastPathComponent
            importRecoveryKey = ""
            statusMessage = nil
        } catch {
            importedData = nil
            importedFilename = nil
            errorMessage = safeMessage(for: error)
        }
    }

    private func restore() {
        guard let backupData = importedData, !isRestoring else { return }
        let key = importRecoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isRestoring = true

        Task {
            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    try EncryptedBackupService.restore(
                        from: backupData,
                        encodedRecoveryKey: key
                    )
                }.value
                let result = try await BackupRestoreService.restore(
                    payload,
                    existingCharts: charts,
                    existingInsights: insights,
                    modelContext: modelContext
                )

                importedData = nil
                importedFilename = nil
                importRecoveryKey = ""
                statusMessage = "已還原 \(result.chartCount) 張命盤與 \(result.insightCount) 則筆記或收藏。"
            } catch {
                modelContext.rollback()
                errorMessage = safeMessage(for: error)
            }
            isRestoring = false
        }
    }

    private func safeMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return "備份檔無法處理，請確認檔案與復原金鑰。"
    }
}
