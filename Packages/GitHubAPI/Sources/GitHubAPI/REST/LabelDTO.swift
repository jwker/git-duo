import Foundation

/// 标签 —— `GET /repos/{owner}/{repo}/labels` 的元素，也是 Issue 卡片上那枚胶囊
/// （TECH_SPEC §4.6.2、§9.8、决策 #56）。
///
/// ## `color` **不带 `#`**，而且**两个方向都不带**
///
/// GitHub 用**六位十六进制、不带前缀**（`"d73a4a"`），而 SwiftUI 的 `Color` 要 `#d73a4a`。
/// 本类型**原样保留**服务端的字符串、不做美化 —— 数据层的职责是"把响应说清楚"，
/// 而不是替上层决定怎么显示（同 `IssueDTO.state` 保留 `String` 的理由：
/// 替它拍一个形状，将来形状变了要改的就是这一层）。
///
/// ⚠️ 反向也一样：`POST …/labels` 要求 `color` **同样不带 `#`** ——
/// 顺手补一个 `#` 发过去会被服务端拒掉。两个方向都别美化。
public struct LabelDTO: Sendable, Equatable, Decodable {

    /// 标签名。**同一仓库内唯一** —— 它是去重与选中的键（PRD §5.2 的"已存在则自动选中"）。
    public let name: String

    /// 六位十六进制，**不带 `#`**（如 `d73a4a`）。
    public let color: String

    /// 描述。**可以是 `null`**（早期创建的标签没有它）。
    ///
    /// ⚠️ 本切片**不渲染**描述（PRD §5.2 的标签行只有色点 + 名字），
    /// 保留它是因为它会随列表一起回来 —— 少声明一个字段，就是将来想加时
    /// 又要动一次 DTO（而那时改动会连带影响缓存键与桩件）。
    public let description: String?

    public init(name: String, color: String, description: String? = nil) {
        self.name = name
        self.color = color
        self.description = description
    }
}
