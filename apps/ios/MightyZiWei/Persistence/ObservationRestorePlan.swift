import Foundation
import SwiftData

/// 先檢查所有不可覆寫內容，再與既有還原共用同一次 save。
struct ObservationRestorePlan {
  let observationsToInsert: [SavedObservation]
  let reviewsToInsert: [SavedObservationReview]
  let existingObservations: [SavedObservation]
  let existingReviews: [SavedObservationReview]

  init(payload: ValidatedBackupPayload, modelContext: ModelContext) throws {
    let observations = try modelContext.fetch(FetchDescriptor<SavedObservation>())
    let reviews = try modelContext.fetch(FetchDescriptor<SavedObservationReview>())
    let observationsByID = Dictionary(uniqueKeysWithValues: observations.map { ($0.id, $0) })
    let reviewsByID = Dictionary(uniqueKeysWithValues: reviews.map { ($0.id, $0) })
    var newObservations: [SavedObservation] = []
    var newReviews: [SavedObservationReview] = []
    for incoming in payload.observations {
      if let existing = observationsByID[incoming.id] {
        guard try incoming.hasSameContent(as: ObservationPayload(existing)) else {
          throw ObservationError.immutableConflict
        }
      } else {
        newObservations.append(try incoming.makeModel())
      }
    }
    for incoming in payload.reviews {
      if let existing = reviewsByID[incoming.id] {
        guard try incoming.hasSameContent(as: ObservationReviewPayload(existing)) else {
          throw ObservationError.immutableConflict
        }
      } else {
        newReviews.append(try incoming.makeModel())
      }
    }
    observationsToInsert = newObservations
    reviewsToInsert = newReviews
    existingObservations = payload.observations.compactMap { observationsByID[$0.id] }
    existingReviews = payload.reviews.compactMap { reviewsByID[$0.id] }
  }

  func apply(modelContext: ModelContext, revision: Date) {
    observationsToInsert.forEach(modelContext.insert)
    reviewsToInsert.forEach(modelContext.insert)
    for observation in existingObservations + observationsToInsert {
      observation.modifiedAt = max(observation.modifiedAt, revision)
    }
    for review in existingReviews + reviewsToInsert {
      review.modifiedAt = max(review.modifiedAt, revision)
    }
  }
}
