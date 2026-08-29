import SwiftData
import SwiftUI

struct SavedConversationsView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(ChartAssistantStore.self) private var assistantStore
  @Query(sort: \SavedConversation.updatedAt, order: .reverse)
  private var conversations: [SavedConversation]

  @State private var searchText = ""
  @State private var conversationToRename: SavedConversation?
  @State private var conversationToDelete: SavedConversation?
  @State private var proposedTitle = ""
  @State private var errorMessage: String?

  private var filtered: [SavedConversation] {
    conversations.filter { $0.matchesSearch(searchText) }
  }

  var body: some View {
    List {
      if conversations.isEmpty {
        ContentUnavailableView(
          "尚未保存對話",
          systemImage: "bubble.left.and.bubble.right",
          description: Text("在命盤助理完成問答後，從保存狀態卡主動保存。")
        )
      } else if filtered.isEmpty {
        ContentUnavailableView.search(text: searchText)
      } else {
        ForEach(filtered) { conversation in
          HStack(spacing: 8) {
            NavigationLink {
              SavedConversationDetailView(conversation: conversation)
            } label: {
              VStack(alignment: .leading, spacing: 6) {
                Text(conversation.title)
                  .font(.headline)
                Text(conversation.chartName)
                Text("\(conversation.modelIdentifier)・\(conversation.turns.count) 輪")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text(conversation.updatedAt, format: .dateTime.year().month().day().hour().minute())
                  .font(.caption)
                  .foregroundStyle(.tertiary)
              }
              .padding(.vertical, 4)
              .accessibilityElement(children: .combine)
            }

            Menu {
              Button("重新命名", systemImage: "pencil") {
                conversationToRename = conversation
                proposedTitle = conversation.title
              }
              Button("刪除", systemImage: "trash", role: .destructive) {
                conversationToDelete = conversation
              }
            } label: {
              Label("對話操作", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityIdentifier("conversation.rowMenu.\(conversation.id.uuidString)")
          }
          .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
              conversationToRename = conversation
              proposedTitle = conversation.title
            } label: {
              Label("重新命名", systemImage: "pencil")
            }
          }
          .swipeActions(edge: .trailing) {
            Button("刪除", systemImage: "trash", role: .destructive) {
              conversationToDelete = conversation
            }
          }
        }
      }
    }
    .navigationTitle("已保存對話")
    .searchable(text: $searchText, prompt: "搜尋標題、命盤、模型或內容")
    .alert("重新命名對話", isPresented: renameIsPresented) {
      TextField("對話標題", text: $proposedTitle)
      Button("取消", role: .cancel) {}
      Button("儲存") {
        conversationToRename?.rename(to: proposedTitle)
        save(errorText: "無法重新命名本機對話。")
        conversationToRename = nil
      }
    } message: {
      Text("對話只保存在本機，不會納入 iCloud 同步或加密備份。")
    }
    .confirmationDialog(
      "刪除這份已保存對話？",
      isPresented: deleteIsPresented,
      titleVisibility: .visible
    ) {
      Button("刪除對話", role: .destructive) {
        guard let conversationToDelete else { return }
        delete(conversationToDelete)
        self.conversationToDelete = nil
      }
      Button("取消", role: .cancel) {
        conversationToDelete = nil
      }
    } message: {
      Text("這只會刪除本機保存副本，目前仍在畫面上的對話不會被清除。")
    }
    .alert("操作未完成", isPresented: errorIsPresented) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "未知錯誤")
    }
  }

  private var renameIsPresented: Binding<Bool> {
    Binding(
      get: { conversationToRename != nil },
      set: { if !$0 { conversationToRename = nil } }
    )
  }

  private var deleteIsPresented: Binding<Bool> {
    Binding(
      get: { conversationToDelete != nil },
      set: { if !$0 { conversationToDelete = nil } }
    )
  }

  private var errorIsPresented: Binding<Bool> {
    Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )
  }

  private func delete(_ conversation: SavedConversation) {
    let deletedID = conversation.id
    modelContext.delete(conversation)
    if save(errorText: "無法刪除本機對話。") {
      assistantStore.reconcileDeletedSavedConversation(deletedID)
    }
  }

  @discardableResult
  private func save(errorText: String) -> Bool {
    do {
      try modelContext.save()
      return true
    } catch {
      modelContext.rollback()
      errorMessage = errorText
      return false
    }
  }
}

struct SavedConversationExportPrivacyGuard: Equatable, Sendable {
  let includedFields = ["命盤名稱", "出生日期與時間", "模型與完整問答"]

  var fieldSummary: String {
    includedFields.joined(separator: "、")
  }
}

private struct SavedConversationDetailView: View {
  let conversation: SavedConversation

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(ChartAssistantStore.self) private var assistantStore
  @State private var exportConfirmed = false
  @State private var showsExportConfirmation = false
  @State private var showsDeleteConfirmation = false
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
        VStack(alignment: .leading, spacing: 8) {
          Text(conversation.title)
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
          Label(conversation.chartName, systemImage: "person.text.rectangle")
          LabeledContent("命盤資料", value: conversation.chartDetail)
          LabeledContent("當時模型", value: conversation.modelIdentifier)
          Text("這是你主動保存的本機副本，不會自動同步。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .cardStyle()

        ForEach(Array(conversation.turns.enumerated()), id: \.element.id) { index, turn in
          VStack(alignment: .leading, spacing: 12) {
            Text("第 \(index + 1) 輪")
              .font(.headline)
            Text("問題")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(turn.question)
            Divider()
            Text("回答")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(turn.answer)
              .textSelection(.enabled)
            if turn.status == .unsupported {
              Label("當時無法用命盤回答", systemImage: "questionmark.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !turn.evidenceFactIDs.isEmpty {
              Label(
                "保留 \(turn.evidenceFactIDs.count) 項命盤依據",
                systemImage: "checkmark.seal"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
          .cardStyle()
        }
      }
      .padding()
    }
    .navigationTitle("對話內容")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if exportConfirmed {
          ShareLink(item: conversation.exportText()) {
            Label("匯出純文字", systemImage: "square.and.arrow.up")
          }
          .accessibilityIdentifier("conversation.export")
        } else {
          Button {
            showsExportConfirmation = true
          } label: {
            Label("確認個人資料後匯出", systemImage: "exclamationmark.shield")
          }
          .accessibilityIdentifier("conversation.confirmExport")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button(role: .destructive) {
          showsDeleteConfirmation = true
        } label: {
          Label("刪除對話", systemImage: "trash")
        }
        .accessibilityIdentifier("conversation.delete")
      }
    }
    .confirmationDialog(
      "確認匯出個人資料",
      isPresented: $showsExportConfirmation,
      titleVisibility: .visible
    ) {
      Button("我已確認，顯示匯出按鈕") { exportConfirmed = true }
      Button("取消", role: .cancel) {}
    } message: {
      Text(
        "純文字將包含\(SavedConversationExportPrivacyGuard().fieldSummary)：命盤名稱「\(conversation.chartName)」、命盤資料「\(conversation.chartDetail)」。下一步仍需點選匯出按鈕才會開啟系統分享選單。"
      )
    }
    .confirmationDialog(
      "刪除這份已保存對話？",
      isPresented: $showsDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("刪除對話", role: .destructive) { deleteConversation() }
      Button("取消", role: .cancel) {}
    } message: {
      Text("這只會刪除本機保存副本，目前命盤助理畫面上的對話不會被清除。")
    }
    .alert("操作未完成", isPresented: errorIsPresented) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "無法刪除本機對話。")
    }
  }

  private var errorIsPresented: Binding<Bool> {
    Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )
  }

  private func deleteConversation() {
    let deletedID = conversation.id
    modelContext.delete(conversation)
    do {
      try modelContext.save()
      assistantStore.reconcileDeletedSavedConversation(deletedID)
      dismiss()
    } catch {
      modelContext.rollback()
      errorMessage = "無法刪除本機對話，目前內容仍保留。"
    }
  }
}
