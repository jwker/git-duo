import GitDuoCore
import GitDuoDesign
import SwiftUI

/// 我的 Tab 根页。
/// 依据：PRD §4.12。入口：我的 Star / 我的收藏 / 设置。
///
/// ⚠️ **切片 1 的唯一例外**：本屏整体仍是骨架屏，只有「退出登录」是**真实现**。
///    原因是 1.8 真机验收的第 6/7 步（退出登录 → 回登录页 · GitHub 侧授权真被撤销）
///    必须有入口可点，而原型里登出走的是「我的 → 设置 → 退出登录」，**设置页属切片 9**。
///    ⇒ 切片 9 把本行迁进设置页时，**连同确认弹层一起补上**（原型那段：
///    「退出登录？」+「撤销 GitHub 侧的授权」），并删除这里的例外与注释。
///
/// ⚠️ 有意**不做**二次确认：按验收口径，确认弹层属切片 9。此处一键即登出
///    （清本机令牌 + 撤销 GitHub 侧授权，恢复成本 = 重新登录一次）。
struct ProfileView: View {

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            SkeletonScreen(
                title: "我的",
                slice: "骨架占位 · 切片 9 落地",
                reference: "PRD §4.12 · 入口：我的 Star / 我的收藏 / 设置"
            )

            signOutRow
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.background)
        .navigationTitle("我的")
    }

    /// 退出登录入口。
    ///
    /// 铁律：这是**内容层** ⇒ 底用实色 `surface` + 描边，**绝不用 `.glassEffect`**（§10.3）。
    private var signOutRow: some View {
        Button {
            Task { await env.signOut() }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("退出登录")
                    .font(Theme.Font.bodyStrong)
                Spacer()
            }
            .foregroundStyle(Theme.Palette.destructive)
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity)
            .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Palette.borderSoft)
            }
            // 整行可点（否则只有图标与文字那两小块响应点击）
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environment(AppEnvironment(tokenStore: InMemoryTokenStore()))
}
