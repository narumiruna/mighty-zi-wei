import SwiftData

/// v1 的既有模型保持原樣，以對應未標版本的既有 store checksum。
enum AppModelSchemaV1: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
  static var models: [any PersistentModel.Type] {
    [SavedChart.self, SavedInsight.self, SavedConversation.self, CloudDeletion.self]
  }
}

enum AppModelSchemaV2: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
  static var models: [any PersistentModel.Type] {
    AppModelSchemaV1.models + [SavedObservation.self, SavedObservationReview.self]
  }
}

enum AppModelSchemaMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [AppModelSchemaV1.self, AppModelSchemaV2.self]
  }
  static var stages: [MigrationStage] {
    [.lightweight(fromVersion: AppModelSchemaV1.self, toVersion: AppModelSchemaV2.self)]
  }
}
