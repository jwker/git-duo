import GitDuoDesign
import GitDuoKit
import SwiftUI
import UIKit

/// markdown 正文里的一张图（2026-10-12 新增，`REVIEW-CHECKLIST` **第 58 条**）。
///
/// ## 两条路，按地址的**归属**分（不是按"能不能加载"分）
///
/// | 地址 | 走哪条 | 为什么 |
/// |---|---|---|
/// | 仓库内（`../images/x.png`、同一个仓库的 `github.com/.../blob/...`） | `MarkdownImageStore`（`rawFile`，带令牌） | 私有仓库的图**必须**带令牌才取得到（`TECH_SPEC §10.6` 那条例外：`AsyncImage` 只对公开图片成立）；分支也要跟着当前选的那一个 |
/// | 仓库外（`https://user-images…`） | `AsyncImage` | Issue / PR 评论、Release 说明里的图是 GitHub 上传后给的**绝对地址**，公开、无需令牌 ⇒ 交给系统那套（带缓存），零额外成本 |
/// | 解析不出落点（页内锚点、跳出仓库根的相对地址、指向目录） | 占位块 | 猜不出它想去哪儿，就不去取 |
///
/// ⚠️ 第二行是**白拿的一大块**：`CommentRow` / `ReleaseNotesSheet` 那两处**不传**
/// `MarkdownImageContext`（它们手上没有仓库与分支），但那里面的图仍然会显示出来 ——
/// 因为那些图本来就是绝对地址。
///
/// ## ⚠️ 版式的两条「规格未给」
///
/// 原型 `.markdown` 一族**连一条 `img` 规则都没有**（正文里一次都没画过图），
/// 所以下面这两处没有依据、只能取"最不发明"的那种：
///
/// 1. **图片圆角**：不加。图片与代码面 / 卡片不同，它自带内容 —— 裁掉四个角是
///    改了用户的内容，而原型没说可以改；
/// 2. **占位块的高度**：`Theme.Spacing.page × 8`（= 128）。取既有令牌的倍数、
///    不新造裸数字；量级上一眼能看出"这里会有一张图"，又不至于一屏只剩一个占位块。
///
/// ## ⚠️ 布局会跳一下
///
/// 图片下载完才知道它的高度 ⇒ 占位块（128）换成真图时页面会往下弹一点。
/// 这是**原生渲染与网页 `<img>` 的固有差别**（浏览器拿到尺寸前也会留白，只是它留的
/// 是由旧内容 / `width` / `height` 属性算出来的）。要消掉得先解析图片头拿尺寸、
/// 或者要求作者写 `width` / `height` —— 两者都超出这一版，如实登记在第 58 条。
struct MarkdownImage: View {

    /// 原始地址（相对地址就是源码里那一串）。
    let url: URL

    /// 替代文字（**可以为空**）。
    let alt: String

    /// 取仓库内图片所需的上下文；`nil` = 这一处只画得动仓库外的绝对地址。
    let context: MarkdownImageContext?

    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        switch destination {
        case let .repository(path):
            if let context {
                repositoryImage(path, context: context)
            } else {
                // `destination` 已经保证这一档有 `context`（见下），这里只是不让
                // 编译器替我们做一个不存在的假设。
                placeholderFailure
            }

        case let .external(remote):
            externalImage(remote)

        case .none:
            placeholderFailure
        }
    }

    // MARK: - 地址落在哪儿

    private enum Destination {
        case repository(RepoPath)
        case external(URL)
        case none
    }

    /// ⚠️ 分档**复用 `RepoLinkResolver`**（与正文链接同一份判据）：
    /// 相对地址（含 `..` / `./` / 越界）、同仓库的 `github.com/.../blob/...`、
    /// 站点根相对、`#锚点` —— 这些形状的判定只有一处实现，
    /// 另写一份的话"图片"和"链接"迟早会对同一个地址给出不同答案。
    private var destination: Destination {
        let target = RepoLinkResolver.target(
            for: url,
            // 没有上下文时传空串：相对地址仍会被判成 `.file`，而下面那条
            // `guard` 会把它落到"画不出来"——**不会**拿空仓库名去发请求。
            fullName: context?.fullName ?? "",
            baseDirectory: context?.baseDirectory ?? .root
        )

        switch target {
        case let .file(path):
            guard context != nil else { return .none }
            return .repository(path)

        case let .external(remote):
            return .external(remote)

        case .directory, .anchor, .unresolved:
            // 指向目录 / 页内锚点 / 跳出仓库根的相对地址 —— 都不是一张图。
            return .none
        }
    }

    // MARK: - 仓库内（自建通道）

    private func repositoryImage(_ path: RepoPath, context: MarkdownImageContext) -> some View {
        Group {
            if let loaded {
                imageSurface(Image(uiImage: loaded))
            } else if failed {
                placeholderFailure
            } else {
                placeholderLoading
            }
        }
        // ⚠️ `id:` 用地址而不是 `path`：`ForEach` 复用同一个视图位置时
        //    `@State` 会跟着留下，换了地址要**先把上一张清掉** ——
        //    不清的话新图到位之前那一瞬画的是旧图（看起来像"图换错了"）。
        .task(id: url.absoluteString) {
            loaded = nil
            failed = false
            loaded = await context.store.image(
                fullName: context.fullName, ref: context.ref, path: path
            )
            failed = loaded == nil
        }
    }

    // MARK: - 仓库外（系统那套）

    private func externalImage(_ remote: URL) -> some View {
        AsyncImage(url: remote) { phase in
            switch phase {
            case let .success(image):
                imageSurface(image)
            case .failure:
                placeholderFailure
            case .empty:
                placeholderLoading
            @unknown default:
                placeholderLoading
            }
        }
    }

    // MARK: - 三种画面

    private func imageSurface(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            // ⚠️ 上限取**图片自己的宽度**（`UIImage.size` 已经是 pt）：不加这一条，
            //    一张 16×16 的徽章会被 `resizable` 放大到整屏宽 —— 而 README 开头
            //    那排"构建状态 / 许可证"徽章正是小图。容器更窄时它自然取容器宽。
            .frame(maxWidth: imageWidthLimit, alignment: .leading)
            .accessibilityLabel(MarkdownCopy.imageAccessibilityLabel(alt: alt))
    }

    /// `imageSurface` 的宽度上限 —— **图片自己的宽度**。
    ///
    /// ⚠️ 只有**本地已解码**那一档（`.repository`）拿得到原始尺寸：`AsyncImage`
    /// 成功时给的 `Image` 不暴露尺寸 ⇒ 那一档（`loaded == nil`）不设上限、
    /// 由容器宽决定。代价如实说：**仓库外的图里，很小的图标会被放大到整屏宽**。
    /// 这是"系统那套拿不到尺寸"的直接结果，不是取舍 —— 真要治，得自己取字节
    /// 再 `UIImage(data:)`，那就等于把绝对地址也拉进自建通道（第 58 条登记了这条）。
    private var imageWidthLimit: CGFloat? { loaded?.size.width }

    private var placeholderLoading: some View {
        placeholder(symbol: GitHubIcon.image, text: MarkdownCopy.imageLoadingText)
    }

    private var placeholderFailure: some View {
        placeholder(
            symbol: GitHubIcon.imageFailure,
            text: MarkdownCopy.imageFailureText(alt: alt)
        )
    }

    /// 占位块（加载中 / 取不到共用一套版式，只有图标与那句话不同）。
    ///
    /// ⚠️ 读屏标签就是那行文字 —— 它是**唯一**说明"这里本来有一张图"的东西，
    /// 抹掉它等于让读屏用户以为这一段正文里什么都没有。
    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.Palette.textSecondary)

            Text(text)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.m)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Spacing.page * 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Palette.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .stroke(Theme.Palette.borderSoft, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// ⚠️ 这个 `#Preview` 里**只有仓库外那一档**能真的出图（`AsyncImage` 打远程地址）。
/// 仓库内那一档需要 `MarkdownImageContext`（真数据源 + 仓库 + 分支），
/// 在预览里造不出来 —— 它靠真机目视（走查第 58 条的待办项）。
#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            MarkdownImage(
                url: URL(string: "https://avatars.githubusercontent.com/u/1?s=200")!,
                alt: "一张公开的图",
                context: nil
            )

            MarkdownImage(
                url: URL(string: "https://example.invalid/missing.png")!,
                alt: "取不到的图，落到占位块",
                context: nil
            )

            MarkdownImage(
                url: URL(string: "../images/x.png")!,
                alt: "仓库内相对地址、而这一处没有上下文",
                context: nil
            )
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
