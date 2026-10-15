import SwiftUI

import GitDuoKit

/// **外观偏好** —— 设置页「主题」行的三档（走查第 69 条，2026-10-15）。
///
/// 依据：PRD §4.20（2026-10-15 补记）、TECH_SPEC §9.15（「不提供切换器」的旧口径
/// 同日推翻补记 —— 那是"本期仅浅色"年代的产物，深色接通后切换器随之成立）。
///
/// ## 存储口径（两条既定规矩的交汇点）
///
/// - **非账号命名空间**：TECH_SPEC §3.8 明写「登出不删除与账号无关的 UI 偏好」
///   且点名了主题 —— 所以它存 `UserDefaults.standard` 的**裸键**，
///   不进 `UserDefaultsStores` 那套按账号命名空间的 actor（那些管的是账号数据）。
/// - **`@AppStorage` 直读直写**：它没有可测的领域逻辑（三档枚举没有分支值得单测），
///   不需要 ViewModel / Store —— 跟「最近访问」那种要 actor 管并发的是两码事。
enum AppAppearance: String, CaseIterable, Identifiable {

    /// 跟随系统 —— `preferredColorScheme(nil)`，App 不干预。
    case system

    /// 强制浅色 —— 系统深色也进不来（这正是切换器的语义）。
    case light

    /// 强制深色。
    case dark

    var id: String { rawValue }

    /// `UserDefaults` 的键。⚠️ **裸键、不带账号前缀**（见类型说明）。
    static let storageKey = "appearance"

    /// 三档的展示文案（正本在 `ProfileCopy`，同页其他文案同一出处）。
    var label: String {
        switch self {
        case .system: ProfileCopy.appearanceFollowSystem
        case .light: ProfileCopy.appearanceLight
        case .dark: ProfileCopy.appearanceDark
        }
    }

    /// 传给 `.preferredColorScheme` 的值：**只有强制档才返回非 nil**。
    ///
    /// ⚠️ `nil` = 不干预 = 跟随系统 —— 不是"没有偏好"，是"把决定权还给系统"。
    /// 传 `.light`/`.dark` 是全局强转，整个窗口被锁死在该模式。
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// 从 `UserDefaults` 读回（读到旧值 / 脏值时按"跟随系统"降级 —— 不崩、不猜）。
    static func stored(_ raw: String?) -> AppAppearance {
        raw.flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}
