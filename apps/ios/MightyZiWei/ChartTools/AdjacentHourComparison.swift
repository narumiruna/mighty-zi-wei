import Foundation

enum AdjacentHourPosition: String, Sendable {
  case previous
  case current
  case next
}

enum AdjacentHourFactSubject: Hashable, Sendable {
  case lifePalace
  case bodyPalace
  case fiveElementBureau
  case mainStar(Star)
  case transformation(TransformationKind)
}

enum AdjacentHourFactValue: Equatable, Sendable {
  case palace(kind: PalaceKind, branch: EarthlyBranch)
  case fiveElementBureau(FiveElementBureau)
  case starPosition(branch: EarthlyBranch, palace: PalaceKind)
  case transformationPosition(star: Star, branch: EarthlyBranch, palace: PalaceKind)
}

struct AdjacentHourFactDifference: Equatable, Sendable {
  let subject: AdjacentHourFactSubject
  let currentValue: AdjacentHourFactValue
  let adjacentValue: AdjacentHourFactValue
}

struct AdjacentHourChartSnapshot: Equatable, Sendable {
  let position: AdjacentHourPosition
  let birthProfile: BirthProfile
  let hourBranch: EarthlyBranch
  let lifePalace: ChartPalace
  let bodyPalace: ChartPalace
  let fiveElementBureau: FiveElementBureau
  let mainStars: [StarPlacement]
  let transformations: [Transformation]
}

struct AdjacentHourComparison: Equatable, Sendable {
  let previous: AdjacentHourChartSnapshot
  let current: AdjacentHourChartSnapshot
  let next: AdjacentHourChartSnapshot
  let previousDifferences: [AdjacentHourFactDifference]
  let nextDifferences: [AdjacentHourFactDifference]
}

enum AdjacentHourComparisonError: Error, Equatable, Sendable {
  case adjacentHourUnavailable(AdjacentHourPosition)
  case incompleteSnapshot(AdjacentHourPosition)
}

struct AdjacentHourComparisonBuilder: Sendable {
  private let calculator = ZiWeiCalculator()

  func make(from profile: BirthProfile) throws -> AdjacentHourComparison {
    let currentChart = try calculator.calculate(profile)
    let previousChart = try adjacentChart(
      from: profile,
      currentBranch: currentChart.hourBranch,
      position: .previous
    )
    let nextChart = try adjacentChart(
      from: profile,
      currentBranch: currentChart.hourBranch,
      position: .next
    )

    let previous = try makeSnapshot(from: previousChart, position: .previous)
    let current = try makeSnapshot(from: currentChart, position: .current)
    let next = try makeSnapshot(from: nextChart, position: .next)

    return AdjacentHourComparison(
      previous: previous,
      current: current,
      next: next,
      previousDifferences: differences(current: current, adjacent: previous),
      nextDifferences: differences(current: current, adjacent: next)
    )
  }

  private func adjacentChart(
    from profile: BirthProfile,
    currentBranch: EarthlyBranch,
    position: AdjacentHourPosition
  ) throws -> ZiWeiChart {
    let targetIndex: Int
    let targetStartDate: LocalDate
    let currentIndex = currentBranch.rawValue

    switch position {
    case .previous:
      targetIndex = (currentIndex + 11) % 12
      if currentBranch == .zi {
        targetStartDate = try ziHourStartDate(for: profile)
      } else if currentBranch == .chou {
        targetStartDate = try addingDays(-1, to: profile.localDate)
      } else {
        targetStartDate = profile.localDate
      }
    case .next:
      targetIndex = (currentIndex + 1) % 12
      if currentBranch == .zi {
        targetStartDate = try addingDays(1, to: ziHourStartDate(for: profile))
      } else {
        targetStartDate = profile.localDate
      }
    case .current:
      return try calculator.calculate(profile)
    }

    let targetBranch = EarthlyBranch(rawValue: targetIndex)!
    let startHour = targetBranch == .zi ? 23 : targetIndex * 2 - 1

    for minuteOffset in 0..<120 {
      let totalMinutes = startHour * 60 + minuteOffset
      let date = try addingDays(totalMinutes / (24 * 60), to: targetStartDate)
      let minuteOfDay = totalMinutes % (24 * 60)
      let candidate = BirthProfile(
        localDate: date,
        localTime: LocalTime(hour: minuteOfDay / 60, minute: minuteOfDay % 60),
        calendarIdentifier: profile.calendarIdentifier,
        timeZoneIdentifier: profile.timeZoneIdentifier
      )

      do {
        let chart = try calculator.calculate(candidate)
        if chart.hourBranch == targetBranch {
          return chart
        }
      } catch BirthProfileValidationError.nonexistentLocalTime {
        continue
      } catch BirthProfileValidationError.dateOutOfRange {
        continue
      }
    }

    throw AdjacentHourComparisonError.adjacentHourUnavailable(position)
  }

  private func ziHourStartDate(for profile: BirthProfile) throws -> LocalDate {
    if profile.localTime.hour == 0 {
      return try addingDays(-1, to: profile.localDate)
    }
    return profile.localDate
  }

  private func addingDays(_ days: Int, to localDate: LocalDate) throws -> LocalDate {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = DateComponents(
      timeZone: calendar.timeZone,
      year: localDate.year,
      month: localDate.month,
      day: localDate.day,
      hour: 12
    )
    guard let date = calendar.date(from: components),
      let shifted = calendar.date(byAdding: .day, value: days, to: date)
    else {
      throw AdjacentHourComparisonError.adjacentHourUnavailable(days < 0 ? .previous : .next)
    }
    let result = calendar.dateComponents([.year, .month, .day], from: shifted)
    guard let year = result.year, let month = result.month, let day = result.day else {
      throw AdjacentHourComparisonError.adjacentHourUnavailable(days < 0 ? .previous : .next)
    }
    return LocalDate(year: year, month: month, day: day)
  }

  private func makeSnapshot(
    from chart: ZiWeiChart,
    position: AdjacentHourPosition
  ) throws -> AdjacentHourChartSnapshot {
    guard let lifePalace = chart.palaces.first(where: { $0.kind == .life }),
      let bodyPalace = chart.palaces.first(where: \.isBodyPalace)
    else {
      throw AdjacentHourComparisonError.incompleteSnapshot(position)
    }

    let placementsByStar = Dictionary(uniqueKeysWithValues: chart.stars.map { ($0.star, $0) })
    let mainStars = Star.allCases
      .filter { $0.category == .main }
      .compactMap { placementsByStar[$0] }
    let transformationsByKind = Dictionary(
      uniqueKeysWithValues: chart.transformations.map { ($0.kind, $0) })
    let transformations = TransformationKind.allCases.compactMap { transformationsByKind[$0] }

    guard mainStars.count == 14, transformations.count == TransformationKind.allCases.count else {
      throw AdjacentHourComparisonError.incompleteSnapshot(position)
    }

    return AdjacentHourChartSnapshot(
      position: position,
      birthProfile: chart.birthProfile,
      hourBranch: chart.hourBranch,
      lifePalace: lifePalace,
      bodyPalace: bodyPalace,
      fiveElementBureau: chart.fiveElementBureau,
      mainStars: mainStars,
      transformations: transformations
    )
  }

  private func differences(
    current: AdjacentHourChartSnapshot,
    adjacent: AdjacentHourChartSnapshot
  ) -> [AdjacentHourFactDifference] {
    let currentFacts = facts(from: current)
    let adjacentFacts = facts(from: adjacent)

    return factSubjects.compactMap { subject in
      guard let currentValue = currentFacts[subject],
        let adjacentValue = adjacentFacts[subject],
        currentValue != adjacentValue
      else {
        return nil
      }
      return AdjacentHourFactDifference(
        subject: subject,
        currentValue: currentValue,
        adjacentValue: adjacentValue
      )
    }
  }

  private var factSubjects: [AdjacentHourFactSubject] {
    [.lifePalace, .bodyPalace, .fiveElementBureau]
      + Star.allCases.filter { $0.category == .main }.map(AdjacentHourFactSubject.mainStar)
      + TransformationKind.allCases.map(AdjacentHourFactSubject.transformation)
  }

  private func facts(
    from snapshot: AdjacentHourChartSnapshot
  ) -> [AdjacentHourFactSubject: AdjacentHourFactValue] {
    var result: [AdjacentHourFactSubject: AdjacentHourFactValue] = [
      .lifePalace: .palace(
        kind: snapshot.lifePalace.kind,
        branch: snapshot.lifePalace.stemBranch.branch
      ),
      .bodyPalace: .palace(
        kind: snapshot.bodyPalace.kind,
        branch: snapshot.bodyPalace.stemBranch.branch
      ),
      .fiveElementBureau: .fiveElementBureau(snapshot.fiveElementBureau),
    ]

    for placement in snapshot.mainStars {
      result[.mainStar(placement.star)] = .starPosition(
        branch: placement.branch,
        palace: placement.palace
      )
    }
    for transformation in snapshot.transformations {
      result[.transformation(transformation.kind)] = .transformationPosition(
        star: transformation.star,
        branch: transformation.branch,
        palace: transformation.palace
      )
    }
    return result
  }
}
