import SwiftUI

/// 弹层里的四件通用零件 —— 原型 `styles/05-overlays.css` 的 `.sheet-title` /
/// `.sheet-row` / `.sheet-hint` / `.sheet-input`（+ `03-components.css` 的 `.btn`）。
///
/// ```css
/// .sheet{padding:8px 10px 12px}                       /* 容器内边距，由各弹层自己加 */
/// .sheet-title{font-size:12px;font-weight:700;color:var(--text3);
///              padding:8px 8px 6px;text-transform:uppercase;letter-spacing:.4px}
/// .sheet-row{display:flex;align-items:center;gap:10px;padding:12px 10px;
///            border-radius:10px;font-size:14.5px;font-weight:500}
/// .sheet-row:active{background:var(--chip)}
/// .sheet-input{width:100%;border:1px solid var(--border);border-radius:10px;
///              padding:10px 12px;font-size:14px;background:var(--bg);color:var(--text)}
/// .sheet-hint{font-size:10.5px;color:var(--text3);padding:6px 8px 2px;line-height:1.5}
/// ```
///
/// ## 为什么它们进设计包（判据 #43）
///
/// 四件都只收基础类型（`String` / `Bool` / 一个回执闭包 / 一个 `Binding<String>`），
/// **不认识**任何领域模型 ⇒ 满足"只收基础类型且与业务无关"。
/// 它们与 `Toast` / `ToastCenter` 同属**导航层原语**（`TECH_SPEC §8.4`），
/// 放在设计包才能被切片 7 / 8 / 9 的弹层直接复用。
///
/// ⚠️ **已知的一处私有副本**：`Search/Components/UserProfileSheet.swift` 里那个
/// `private struct SheetActionButton` 是本包 `ActionButton` 的复制品
/// （切片 5 落地时设计包里还没有这一件）。收拢它是切片 7 / 8 动那一带时顺手的事，
/// 已登记在 `REVIEW-CHECKLIST §5` —— 两处的 `.btn` 视觉是逐字相同的，
/// 这里**不**顺手改切片 5 已验收的页面。
///
/// ## 它们是内容层
///
/// 弹层里**全是实色，不加 Liquid Glass**（§10.2 —— 玻璃只用于导航层外框，
/// 而弹层自身的材质由系统 `presentationDetents` 提供）。

// MARK: - 标题

/// 弹层标题：小号大写灰字（原型 `.sheet-title`）。
public struct SheetTitle: View {

    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            // 原型 12px bold ⇒ 本仓那一档是 `sectionLabel`（`.caption` 12 + bold）。
            .font(Theme.Font.sectionLabel)
            .tracking(0.4)
            .foregroundStyle(Theme.Palette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 原型 `padding:8px 8px 6px`（8 是 `Spacing.s`，6 不在 4pt 阶里 ⇒ 写原值）。
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, 6)
    }
}

// MARK: - 行

/// 弹层里的一行：图标 + 标题 +（可选）右侧内容。
///
/// ⚠️ 它与设计包的 `LinkRow` **不是同一件**：`LinkRow` 画的是页面里的 `.menu-item`
/// （`padding:13px 14px`、字号 14.5/550、图标 19），而这一件是弹层里的 `.sheet-row`
/// （`padding:12px 10px`、字号 14.5/500、图标 18）。两者数值不同、容器不同，
/// 合成一件会让其中一处偏离原型，而偏离处看起来仍然"像一行菜单"。
public struct SheetRow<Trailing: View>: View {

    public let systemImage: String?

    public let title: String

    /// 右侧内容（原型里的 `✓` / `›` / 一枚胶囊）。默认什么都不画。
    private let trailing: Trailing

    private let action: () -> Void

    public init(
        systemImage: String? = nil,
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.systemImage = systemImage
        self.title = title
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    // 原型 `.sheet-row svg{width:18px;height:18px;stroke:var(--text2)}`。
                    Image(systemName: systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }

                Text(title)
                    // 原型 14.5px/500 ⇒ 最近的一档是 `rowTitle`（`.subheadline` 15）。
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                trailing
            }
            // 原型 `padding:12px 10px`。
            .padding(.vertical, Theme.Spacing.m)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SheetRowStyle())
    }
}

extension SheetRow where Trailing == EmptyView {

    /// 不带右侧内容的那一种。
    ///
    /// ⚠️ **它是"写不写 `action:` 标签"那个陷阱的来源**：`SheetRow(systemImage:title:) { … }`
    /// 会选中这一个（尾随闭包绑到 `action:`），而不是上面那个带 `trailing:` 的重载 ——
    /// 于是写的人以为自己在给右侧内容，实际那块内容被丢掉了。
    /// 所以**要传右侧内容时必须把 `action:` 标签写出来**：
    /// `SheetRow(systemImage:, title:, action: {}) { 右侧内容 }`。
    public init(
        systemImage: String? = nil,
        title: String,
        action: @escaping () -> Void
    ) {
        self.init(systemImage: systemImage, title: title, action: action) { EmptyView() }
    }
}

/// 按下时的那一层底色（原型 `.sheet-row:active{background:var(--chip)}`）。
///
/// `.buttonStyle(.plain)` 不给任何按压反馈，而这一条反馈是"我点到了"的唯一迹象
/// —— 弹层里的行没有 `NavigationLink` 的高亮可用。
private struct SheetRowStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(configuration.isPressed ? Theme.Palette.surfaceSunken : .clear)
            )
    }
}

// MARK: - 说明

/// 弹层底部的小号灰字说明（原型 `.sheet-hint`）。
public struct SheetHint: View {

    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            // 原型 10.5px ⇒ 本仓那一档是 `caption`（`.caption2` 11）。
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .lineSpacing(Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 原型 `padding:6px 8px 2px`。
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, 6)
            .padding(.bottom, Theme.Spacing.xxs)
    }
}

// MARK: - 输入框

/// 弹层里的单行输入（原型 `.sheet-input`）。
public struct SheetField: View {

    private let placeholder: String

    @Binding private var text: String

    public init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        TextField(placeholder, text: $text)
            // 原型 14px ⇒ 最近的一档是 `rowTitle`（`.subheadline` 15）。
            .font(Theme.Font.rowTitle)
            .foregroundStyle(Theme.Palette.textPrimary)
            // 原型 `padding:10px 12px`（10 不在 4pt 阶里 ⇒ 写原值）。
            .padding(.vertical, 10)
            .padding(.horizontal, Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    // 原型 `background:var(--bg)` —— 输入框比弹层的白底**更浅一层**，
                    // 那正是本仓 `Palette.background` 与 `Palette.surface` 的关系。
                    .fill(Theme.Palette.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Palette.border, lineWidth: 1)
            )
            .autocorrectionDisabled()
            // ⚠️ `textInputAutocapitalization` 是 **iOS / macCatalyst / tvOS / watchOS 独有**的，
            // macOS 上没有这个修饰符 —— 而本包**同时为 macOS 构建**（测试跑在宿主机上，
            // `swift test` 编的是 `arm64-apple-macos`）。不加这层条件编译，
            // `make test-GitDuoKit` 照样全绿（它不编本包），而 `make verify` 会在这一行炸掉：
            // `value of type 'some View' has no member 'textInputAutocapitalization'`。
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }
}

#Preview {
    @Previewable @State var text = ""

    VStack(alignment: .leading, spacing: 0) {
        SheetTitle("切换分支 · 代码与 Commits 联动")

        // ⚠️ `action:` 这个标签**必须写出来**。写成 `SheetRow(systemImage:title:) { 内容 }`
        // 时，那个尾随闭包会绑到不带标签的那一个 `init(systemImage:title:action:)` 上
        // （`where Trailing == EmptyView`），**于是右侧那块内容根本不画** ——
        // 唯一的迹象是一条 `result of call to 'foregroundStyle' is unused` 的警告，
        // 而闭包体若只是 `{ source = name }` 这种赋值，连那条警告都不会有。
        SheetRow(systemImage: GitHubIcon.branch, title: "main", action: {}) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Palette.accentStrong)
        }
        SheetRow(systemImage: GitHubIcon.branch, title: "feature/auth-refresh", action: {})
        SheetRow(systemImage: GitHubIcon.folder, title: "管理分支…（创建 / 删除 / 合并）", action: {})

        SheetField("提交信息（可选）", text: $text)

        SheetHint("Merge 走 API · 冲突时引导到网页端处理")

        ActionButton(title: "合并", style: .primary, verticalPadding: 12, action: {})
        ActionButton(title: "取消", style: .ghost, verticalPadding: 12, action: {})
            .padding(.top, Theme.Spacing.s)
        ActionButton(title: "删除分支", style: .destructive, verticalPadding: 12, isWorking: true, action: {})
            .padding(.top, Theme.Spacing.s)
    }
    .padding(.horizontal, 10)
    .padding(.top, Theme.Spacing.s)
    .padding(.bottom, Theme.Spacing.m)
    .background(Theme.Palette.surface)
}
