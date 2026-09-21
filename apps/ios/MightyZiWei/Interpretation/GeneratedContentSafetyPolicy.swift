import Foundation

struct GeneratedContentSafetyPolicy: Sendable {
  enum Context {
    case interpretation
    case conversation
  }

  private static let blockedPhrases = [
    "一定會", "必定會", "保證", "替你診斷", "診斷結果是", "治療方案",
    "建議你買進", "建議你賣出", "應該買進", "應該賣出",
    "適合你的投資建議", "適合你的法律建議", "建議採取的訴訟策略",
  ]

  private static let commonDisclaimers = [
    "未必一定會", "不一定會", "不是一定會", "並非一定會", "不代表一定會", "不表示一定會",
    "無法保證", "不是保證", "並非保證", "不代表保證", "不等於保證", "不能視為保證", "不能保證", "不應保證", "不保證",
    "無法替你診斷", "不能替你診斷", "不會替你診斷",
    "無法判定診斷結果是", "不能判定診斷結果是", "不會宣稱診斷結果是",
    "無法提供治療方案", "不能提供治療方案", "不提供治療方案",
  ]

  private static let conversationAdditions = [
    "無法提供健康診斷", "不能提供健康診斷", "不提供健康診斷",
    "無法提供投資建議", "不能提供投資建議", "不提供投資建議",
    "無法提供法律建議", "不能提供法律建議", "不提供法律建議",
  ]

  private static let professionalDisclaimers = [
    "不構成任何投資建議", "不構成投資建議", "不是投資建議", "並非投資建議", "不可視為投資建議",
    "不構成任何法律建議", "不構成法律建議", "不是法律建議", "並非法律建議", "不可視為法律建議",
  ]

  func isUnsafe(_ content: String, context: Context) -> Bool {
    let additions = context == .conversation ? Self.conversationAdditions : []
    let disclaimers = Self.commonDisclaimers + additions + Self.professionalDisclaimers
    let remaining = disclaimers.reduce(content) { $0.replacingOccurrences(of: $1, with: "") }
    return Self.blockedPhrases.contains(where: remaining.contains)
  }
}
