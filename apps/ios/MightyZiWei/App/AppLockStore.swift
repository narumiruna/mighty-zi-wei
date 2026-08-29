import LocalAuthentication
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppLockStore {
  private enum Key {
    static let enabled = "privacy.app-lock.enabled"
  }

  private let defaults: UserDefaults
  private(set) var isEnabled: Bool
  private(set) var isLocked: Bool
  private(set) var isAuthenticating = false
  private(set) var showsPrivacyShield = false
  private(set) var errorMessage: String?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let enabled = defaults.bool(forKey: Key.enabled)
    isEnabled = enabled
    isLocked = enabled
  }

  func enable() async -> Bool {
    guard await evaluate(reason: "啟用 App 鎖，保護命盤與私人內容") else {
      return false
    }
    defaults.set(true, forKey: Key.enabled)
    isEnabled = true
    isLocked = false
    return true
  }

  func disable() async -> Bool {
    guard await evaluate(reason: "關閉 App 鎖") else { return false }
    defaults.set(false, forKey: Key.enabled)
    isEnabled = false
    isLocked = false
    showsPrivacyShield = false
    return true
  }

  func lock() {
    guard isEnabled else { return }
    isLocked = true
  }

  func handleScenePhase(_ phase: ScenePhase) {
    switch phase {
    case .active:
      showsPrivacyShield = false
      if isEnabled, isLocked {
        Task { _ = await unlock() }
      }
    case .inactive, .background:
      showsPrivacyShield = true
      lock()
    @unknown default:
      showsPrivacyShield = true
      lock()
    }
  }

  @discardableResult
  func unlock() async -> Bool {
    guard isEnabled else {
      isLocked = false
      return true
    }
    guard await evaluate(reason: "解鎖很牛的紫微斗數") else { return false }
    isLocked = false
    return true
  }

  func authorizeDataReset() async -> Bool {
    await authorizeDataReset(using: {
      await evaluate(reason: "重建空白本機資料")
    })
  }

  func authorizeDataReset(using authenticate: () async -> Bool) async -> Bool {
    guard isEnabled else { return true }
    return await authenticate()
  }

  func clearError() {
    errorMessage = nil
  }

  private func evaluate(reason: String) async -> Bool {
    guard !isAuthenticating else { return false }
    isAuthenticating = true
    defer { isAuthenticating = false }
    errorMessage = nil

    let context = LAContext()
    context.localizedCancelTitle = "取消"
    context.localizedFallbackTitle = "使用裝置密碼"
    var authorizationError: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authorizationError) else {
      errorMessage = "這台裝置尚未設定 Face ID、Touch ID 或裝置密碼。"
      return false
    }
    do {
      let success = try await context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: reason
      )
      if !success {
        errorMessage = "身分驗證未完成。"
      }
      return success
    } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
      return false
    } catch {
      errorMessage = "無法完成身分驗證，請再試一次。"
      return false
    }
  }
}

struct AppPrivacyShieldPolicy: Sendable {
  func shouldPresent(showsPrivacyShield: Bool, isLocked: Bool) -> Bool {
    showsPrivacyShield || isLocked
  }
}

@MainActor
final class PrivacyShieldWindowPresenter {
  static let shared = PrivacyShieldWindowPresenter()

  private var shieldWindow: UIWindow?
  private weak var previousKeyWindow: UIWindow?

  func setPresented(_ presented: Bool, lockStore: AppLockStore) {
    if presented {
      present(lockStore: lockStore)
    } else {
      dismiss()
    }
  }

  private func present(lockStore: AppLockStore) {
    if shieldWindow?.isHidden == false { return }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard
      let scene = scenes.first(where: { $0.activationState == .foregroundActive })
        ?? scenes.first(where: { $0.activationState == .foregroundInactive })
        ?? scenes.first
    else { return }

    previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
    let controller = UIHostingController(
      rootView: AppLockOverlay().environment(lockStore)
    )
    controller.view.backgroundColor = .clear
    let window = UIWindow(windowScene: scene)
    window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
    window.backgroundColor = .clear
    window.rootViewController = controller
    shieldWindow = window
    window.makeKeyAndVisible()
  }

  private func dismiss() {
    guard let shieldWindow else { return }
    shieldWindow.isHidden = true
    shieldWindow.rootViewController = nil
    self.shieldWindow = nil
    previousKeyWindow?.makeKey()
    previousKeyWindow = nil
  }
}

struct AppLockOverlay: View {
  @Environment(AppLockStore.self) private var lockStore

  var body: some View {
    ZStack {
      Rectangle()
        .fill(.regularMaterial)
        .ignoresSafeArea()
      VStack(spacing: 18) {
        Image(systemName: "lock.shield")
          .font(.system(size: 48))
          .foregroundStyle(.tint)
        Text("App 已鎖定")
          .font(.title.bold())
        Text("命盤、筆記與 AI 對話已隱藏。")
          .foregroundStyle(.secondary)
        Button {
          Task { await lockStore.unlock() }
        } label: {
          if lockStore.isAuthenticating {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else {
            Label("使用 Face ID 或裝置密碼解鎖", systemImage: "faceid")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(lockStore.isAuthenticating)
        .accessibilityIdentifier("privacy.unlock")
      }
      .padding(28)
      .frame(maxWidth: 420)
    }
    .accessibilityAddTraits(.isModal)
  }
}
