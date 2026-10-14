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
/// | 仓库内（`../images/x.png`、同一个仓库的 `github.com/.../blob/...`） | `MarkdownImageStore`（`rawFile`，带令牌） | 私有仓库的图**必须**带令牌才取得到（`TECH_SPEC §10.6` 那条例外）；分支也要跟着当前选的那一个 |
/// | 仓库外（`https://img.shields.io/…`） | 本视图自己取字节（`URLSession.shared`） | Issue / PR 评论、Release 说明、以及 README 里的徽章都是**绝对地址**，公开、**不带令牌** |
/// | 解析不出落点（页内锚点、跳出仓库根的相对地址、指向目录） | 占位块 | 猜不出它想去哪儿，就不去取 |
///
/// ⚠️ 第二行是**白拿的一大块**：`CommentRow` / `ReleaseNotesSheet` 那两处**不传**
/// `MarkdownImageContext`（它们手上没有仓库与分支），但那里面的图仍然会显示出来 ——
/// 因为那些图本来就是绝对地址。
///
/// ## ⚠️ 2026-10-14：仓库外那条从 `AsyncImage` 换成**自己取字节**
///
/// 起因是用户报回"README 里一部分图没出来"（走查第 **64** 条）：
/// 那些图**全都是 SVG**，而 `AsyncImage` 只会给一个 `.failure` —— 我们**看不到字节**，
/// 也就无法区分"取不到"与"取到了但解不出来" ⇒ 占位块只能对用户说「图片加载失败」，
/// 把排查方向指向了网络（而网络上一切正常）。
///
/// 换掉之后**行为与从前一致**：`AsyncImage` 内部用的就是 `URLSession.shared`
/// （含同一份 HTTP 缓存），这里也用它 ⇒ 缓存语义不变，只是这一次字节经过我们的手。
///
/// ⚠️ 两件事必须同时说清（否则下一个读的人会以为这是违规）：
/// 1. **这条请求不带任何凭据** —— 绝对地址是公开图，不注入令牌、不走 `HTTPTransport`；
///    `TECH_SPEC §10.6` 明写这一类可以不进自建通道（"一旦需要令牌就必须走"）。
///    这也正是不把它塞进 `MarkdownImageStore` 的原因：那个店手里握着令牌。
/// 2. 它**不改变仓库内那条**：带令牌的那条仍然走 `rawFile`（私有仓库的图只能这么取）。
///
/// ## ⚠️ 版式的两条「规格未给」
///
/// 原型 `.markdown` 一族**连一条 `img` 规则都没有**（正文里一次都没画过图），
/// 所以下面这两处没有依据、只能取"最不发明"的那种：
///
/// 1. **图片圆角**：不加。图片与代码面 / 卡片不同，它自带内容 —— 裁掉四个角是
///    改了用户的内容，而原型没说可以改；
/// 2. **占位块的尺寸**：**跟着"这张图本该多大"走**，只在太小时保底
///    （`placeholderBox` 那一组，2026-10-14 傍晚按用户裁定改的口径）。
///    ⚠️ 在此之前它是**满宽 × 128 的定值** —— 而 README 开头那排徽章只有 `98×20`，
///    四块拼成一排大白条（用户截图里正是这样）。
///
/// ## ⚠️ 布局会跳一下
///
/// 图片下载完才知道它的高度 ⇒ 占位块换成真图时页面会往下弹一点。
/// 这是**原生渲染与网页 `<img>` 的固有差别**（浏览器拿到尺寸前也会留白，只是它留的
/// 是由旧内容 / `width` / `height` 属性算出来的）。
/// ⚠️ 2026-10-14 起**有 `width` / `height` 的图不再跳**（`MarkdownImageSize` 那一路，
/// HTML 来源的图才可能有），而 markdown 语法写的图仍然跳 —— 因为 markdown 语法里
/// 根本没有尺寸位，那是语法本身的缺口，不是这里偷懒。
///
/// ## ⚠️ 三个尺寸来源，各管一段
///
/// | 来源 | 拿到什么 | 用在哪 |
/// |---|---|---|
/// | HTML `<img width= height=>`（`size`） | 作者声明的宽高 | `imageWidthLimit`（真图别被放大）+ 占位块 |
/// | SVG 字节里自己声明的（`declaredSize`） | 固有宽高 | 占位块（⚠️ 2026-10-14 傍晚新增） |
/// | 真解出来的 `UIImage.size` | 实际宽高 | `imageWidthLimit` |
///
/// **markdown 语法写的图恒为 `nil`**（那个语法里没有尺寸位），所以它只有第三行那份 ——
/// 详细口径见 `MarkdownImageSize` 与 `MarkdownImageBytes.declaredSize` 的类型说明。
///
/// ⚠️ 前两份**逐维合并**（`wouldBeSize`），因为两边各会缺一边：
/// 徽章是"HTML 什么都没写、SVG 写着 98×20"，而 logo 是"HTML 只写了 `width="200"`、
/// 高度得拿 SVG 的宽高比算"。缺一边就落回 128 的大兜底 —— 两张都会。
struct MarkdownImage: View {

    /// 原始地址（相对地址就是源码里那一串）。
    let url: URL

    /// 替代文字（**可以为空**）。
    let alt: String

    /// HTML `<img>` 声明的尺寸（2026-10-14 新增）；markdown 语法写的图是 `nil`。
    let size: MarkdownImageSize?

    /// 取仓库内图片所需的上下文；`nil` = 这一处只画得动仓库外的绝对地址。
    let context: MarkdownImageContext?

    /// `nil` = 还在取；取完就是三档之一。
    ///
    /// ⚠️ 用 `nil` 而不是给 `MarkdownImageOutcome` 加一个 `.loading`：
    /// "还没开始 / 正在取"是**这个视图的状态**，不是取数那条路会给出的结果 ——
    /// 混进 `Outcome` 之后，`MarkdownImageStore` 的返回值里就多了一种它永远不会返回的东西。
    @State private var outcome: MarkdownImageOutcome?

    init(
        url: URL,
        alt: String,
        size: MarkdownImageSize? = nil,
        context: MarkdownImageContext?
    ) {
        self.url = url
        self.alt = alt
        self.size = size
        self.context = context
    }

    var body: some View {
        switch destination {
        case let .repository(path):
            if let context {
                repositoryImage(path, context: context)
            } else {
                // `destination` 已经保证这一档有 `context`（见下），这里只是不让
                // 编译器替我们做一个不存在的假设。
                placeholder(.failed)
            }

        case let .external(remote):
            externalImage(remote)

        case .none:
            placeholder(.failed)
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

    // MARK: - 两条取数路（结果都落进同一个 `outcome`）

    private func repositoryImage(_ path: RepoPath, context: MarkdownImageContext) -> some View {
        resolved
            // ⚠️ `id:` 用地址而不是 `path`：`ForEach` 复用同一个视图位置时
            //    `@State` 会跟着留下，换了地址要**先把上一张清掉** ——
            //    不清的话新图到位之前那一瞬画的是旧图（看起来像"图换错了"）。
            .task(id: url.absoluteString) {
                outcome = nil
                outcome = await context.store.repositoryImage(
                    fullName: context.fullName, ref: context.ref, path: path
                )
            }
    }

    private func externalImage(_ remote: URL) -> some View {
        resolved.task(id: url.absoluteString) {
            outcome = nil
            outcome = await Self.fetchExternal(remote)
        }
    }

    /// 取一张仓库外的图（**不带凭据**，见类型说明第二条）。
    ///
    /// ⚠️ 用 `URLSession.shared` 而不是 `GitHubURLSession.noCache()`：
    /// 后者**摘掉了 `URLCache`**，那是为了"令牌不落盘"（决策 #32）——
    /// 而这里是一个既没有令牌、也没有 Cookie 的公开 GET，
    /// 换过去只会让同一张徽章被反复下载。**与 `AsyncImage` 从前用的是同一个会话。**
    private static func fetchExternal(_ remote: URL) async -> MarkdownImageOutcome {
        guard let (data, _) = try? await URLSession.shared.data(from: remote) else { return .failed }
        // 先解码、后判格式、最后量尺寸（判据见 `MarkdownImageBytes`）。
        guard let image = UIImage(data: data) else {
            return MarkdownImageBytes.looksLikeSVG(data)
                ? .unsupportedFormat(MarkdownImageBytes.declaredSize(in: data))
                : .failed
        }
        return .loaded(image)
    }

    // MARK: - 三档画面

    /// 取数的两条路共用这一层：**只有取数那一步不同**，取完之后画什么完全一样。
    @ViewBuilder
    private var resolved: some View {
        switch outcome {
        case nil:
            placeholderLoading
        case let .loaded(image)?:
            imageSurface(image)
        case let .unsupportedFormat(svgSize)?:
            placeholder(.unsupportedFormat(svgSize))
        case .failed?:
            placeholder(.failed)
        }
    }

    private func imageSurface(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            // ⚠️ 上限见 `imageWidthLimit`：不加这一条，一张 16×16 的徽章会被
            //    `resizable` 放大到整屏宽 —— 而 README 开头那排徽章正是小图。
            .frame(maxWidth: imageWidthLimit(for: image), alignment: .leading)
            .accessibilityLabel(MarkdownCopy.imageAccessibilityLabel(alt: alt))
    }

    /// `imageSurface` 的宽度上限 —— **真实宽度与声明宽度中更小的那个**。
    ///
    /// ## 两边为什么要取小的
    ///
    /// - **真实宽度**：`UIImage.size` 已经是 pt。少了它，小图会被放大到整屏宽。
    /// - **声明宽度**：作者写的 `width="96"` 是"我希望它这么大"。它可能比真实宽度小
    ///   （大图摆小），也可能比真实宽度大（小图摆大 —— **不采用**：那种"声明"通常是
    ///   作者按网页版式写的，硬信它会把一张 16pt 的徽章拉成 96pt）。
    ///
    /// 所以取更小的那个：**声明只能往下压，不能往上拉**。
    private func imageWidthLimit(for image: UIImage) -> CGFloat {
        let actual = image.size.width
        guard let declared = size?.width, declared > 0 else { return actual }
        return min(actual, CGFloat(declared))
    }

    private var placeholderLoading: some View {
        // 加载中时字节还没到手 ⇒ 量不到 SVG 的固有尺寸，只能用 HTML 声明的那份。
        let box = placeholderBox(intrinsic: nil)
        return placeholder(
            symbol: GitHubIcon.image,
            text: MarkdownCopy.imageLoadingText,
            height: box.height,
            width: box.width
        )
    }

    private func placeholder(_ outcome: MarkdownImageOutcome) -> some View {
        switch outcome {
        case let .unsupportedFormat(svgSize):
            // ⚠️ 图标与失败那一档**有意不同**（`doc.questionmark` 而不是警示三角）：
            //    "这一版看不了"不是出错，用警示三角会让人以为哪一步坏了。
            //    字形复用 `unsupportedFile`（"看不了"那个语义），见 `GitHubIcon`。
            let box = placeholderBox(intrinsic: svgSize)
            return placeholder(
                symbol: GitHubIcon.unsupportedFile,
                text: MarkdownCopy.imageUnsupportedFormatText(alt: alt),
                height: box.height,
                width: box.width
            )
        case .loaded, .failed:
            let box = placeholderBox(intrinsic: nil)
            return placeholder(
                symbol: GitHubIcon.imageFailure,
                text: MarkdownCopy.imageFailureText(alt: alt),
                height: box.height,
                width: box.width
            )
        }
    }

    // MARK: - 占位块该多大

    /// 占位块该多大 —— **宽度跟着图片走、高度给一个上限**（2026-10-14 · 用户裁定两轮）。
    ///
    /// ## 两轮裁定
    ///
    /// 1. **当天傍晚**：从前占位块是**满宽 × 128pt** 的定值，而 README 开头那排徽章
    ///    真实尺寸只有 `98×20` 上下 ⇒ 四个占位块吃掉大半屏、正文被挤得很长。
    ///    改成"按图片尺寸、保底可读"（`max(本该的尺寸, 下限)`）。
    /// 2. **当天当晚**：那两个"保底"**自己成了新的病** —— 一张 `98×20` 的徽章被抬到
    ///    `128 × 48`，四张叠起来仍旧是一排灰条。用户的原话是「不好看」。
    ///
    /// ⇒ 现在的规则：
    ///
    /// - **宽度** = 这张图本该的宽度，**不设下限**（文字放不下就截断，别把块撑宽）；
    /// - **高度** = `min(本该的高度, 128)`；一处尺寸都不知道时**不设下限**
    ///   （由那一行文字自己决定）。
    ///
    /// ⚠️ 徽章那一档**已经不在这里**了（它们走 `MarkdownBadgeView`，压根不取字节）
    /// ⇒ 走到这个函数的多半是 SVG logo、失败的大截图这类。
    ///
    /// - Parameter intrinsic: SVG 自己声明的尺寸；非 SVG（或没量到）时是 `nil`。
    /// - Returns: 宽度为 `nil` = **不限宽**（"这张图本该多大"完全不知道时）。
    private func placeholderBox(intrinsic: MarkdownImageSize?) -> (width: CGFloat?, height: CGFloat) {
        guard let wouldBe = wouldBeSize(intrinsic: intrinsic) else { return (nil, 0) }
        return (wouldBe.width, min(wouldBe.height, Self.maximumPlaceholderHeight))
    }

    /// "这张图本该多大" —— **HTML 声明的与 SVG 自己声明的逐维合并**。
    ///
    /// ## ⚠️ 为什么要逐维合并，而不取其中一份
    ///
    /// 两种来源各会缺一边，而缺的那一边正好能从另一份 + 宽高比算出来：
    ///
    /// | 写法 | HTML 声明 | SVG 自己声明 | 该有多大 |
    /// |---|---|---|---|
    /// | 徽章 `<img src="…badge.svg">` | 无 | `98×20` | 98 × 20 |
    /// | logo `<img src="…logo.svg" width="200">` | 宽 200 | 比如 `1024×256` | 200 × 50 |
    ///
    /// 第二行就是这张表存在的理由：**只有宽没有高**时，用 SVG 的宽高比补出高，
    /// 否则那一张又落回 128 的大兜底。
    ///
    /// ⚠️ 宽高比**只用于补缺**，不覆盖任何一方：两边都给了数就各取各的
    /// （作者写的 `width="200"` 是"我希望它这么宽"，不该被固有比例改写）。
    private func wouldBeSize(intrinsic: MarkdownImageSize?) -> (width: CGFloat, height: CGFloat)? {
        var width = size?.width ?? intrinsic?.width
        var height = size?.height ?? intrinsic?.height

        if let intrinsicWidth = intrinsic?.width, let intrinsicHeight = intrinsic?.height,
           intrinsicWidth > 0, intrinsicHeight > 0 {
            let ratio = CGFloat(intrinsicHeight) / CGFloat(intrinsicWidth)
            if width == nil, let height { width = Int((CGFloat(height) / ratio).rounded()) }
            if height == nil, let width { height = Int((CGFloat(width) * ratio).rounded()) }
        }

        guard let width, let height, width > 0, height > 0 else { return nil }
        return (CGFloat(width), CGFloat(height))
    }

    /// 占位高度的**上限**（`Spacing.page × 8` = 128）。
    ///
    /// ⚠️ 这个数原来叫 `defaultPlaceholderHeight`，语义是"一处尺寸信息都没有时占位块
    /// 有 128 高"。2026-10-14 当晚换了方向：**它从"最矮"变成了"最高"** ——
    /// 占位块只负责说明"这里本来有张图"，不该比图本身还占地方。
    /// 一个 128 也够挡住"一张没有尺寸声明的大截图失败"那种最坏情况。
    private static let maximumPlaceholderHeight = Theme.Spacing.page * 8

    /// 占位块（加载中 / 取不到 / 是 SVG 共用一套版式，只有图标与那句话不同）。
    ///
    /// ## ⚠️ 2026-10-14 当晚：它被"做轻"了
    ///
    /// 从前是「`surfaceSunken` 底 + 圆角 + 边框 + 竖排的图标与文字」——
    /// 一屏四个看起来像四条报错，而它们其实只是"这张图没画出来"。
    /// 现在只剩**一行小字**：图标与说明同排、`caption` 字号、次级色、**无底色无边框**。
    ///
    /// - 失败态本来就不该比正文更显眼；
    /// - 一句话说清"这里本来有张图"就够了 —— 图没出来这件事，块再大也不会变好。
    ///
    /// ⚠️ `lineLimit(1)` + 尾部截断是**有意的**：`macOS · Windows · Linux · FreeBSD · web`
    /// 这种长 `alt` 从前会把块撑成两行、把正文挤走。现在它截断，
    /// 而**读屏标签仍是全文**（`accessibilityLabel` 不受截断影响）。
    ///
    /// ⚠️ 高度用 `minHeight` 而不是 `height`：`height` 为 0 时由那一行文字自己决定；
    /// 为 `98×20` 那类小图时正好留出它本来的高度（加载完换真图时不至于再跳一下）。
    /// ⚠️ `width` 为 `nil` 时**占满一行**（"这张图本该多大"完全不知道时的旧行为）。
    private func placeholder(symbol: String, text: String, height: CGFloat, width: CGFloat?) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.textTertiary)
        .frame(maxWidth: width ?? .infinity, alignment: .leading)
        .frame(minHeight: height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// ⚠️ 这个 `#Preview` 里**只有仓库外那一档**能真的出图（自己用 `URLSession` 打远程地址）。
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

            // shields.io 只出 SVG ⇒ 这一条预览的就是"是 SVG"那一档占位块
            // （用户 2026-10-14 报回的四张徽章就是它）。
            MarkdownImage(
                url: URL(string: "https://img.shields.io/badge/Rust-100%25-orange")!,
                alt: "Rust 徽章",
                size: MarkdownImageSize(width: nil, height: 20),
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
