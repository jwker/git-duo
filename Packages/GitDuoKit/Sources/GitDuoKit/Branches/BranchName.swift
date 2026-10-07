import Foundation

/// 分支名校验 —— **纯函数**（TECH_SPEC §9.7.1、PRD §4.8「新建分支」）。
///
/// ## 为什么放在客户端
///
/// 服务端对不合法的分支名回 **422**，而 422 的响应体是 `{message, errors[]}` ——
/// 那不是表单校验的形态：用户读到的是"服务器验证失败"，第一反应是"GitHub 坏了"，
/// 而不是"我这个名字有问题"。所以**在发请求之前**就拦下，并把**具体哪一条规则不满足**
/// 说清楚（`BranchNameCopy`）。
///
/// ## 为什么在领域层
///
/// App target 没有测试 target。而这一串规则是**照 git 的 `check_refname_format` 抄的**
/// —— 抄漏一条不会报错，表现是"某个名字在客户端放行、到服务端吃 422"，
/// 而那又会退回到上面那句被误读的提示。放进本包，它落在 `BranchNameTests` 里。
///
/// ## ⚠️ 有意**不**拦 `@{`
///
/// git 的规则里还禁止 `@{` 序列（`HEAD@{1}` 那种 reflog 记法），
/// 而 TECH_SPEC §9.7.1 与 PRD §4.8 列出的判据**只有八条、不含它**。
/// 规格是正本 ⇒ 这里不加（加了就是"实现比规格严"，同样会出现
/// "文档说可以、App 说不可以"的分歧）。该名字仍会被服务端 422 拦下。
/// **已按"已知偏差"登记**，待用户裁定是否补进规格。
public enum BranchName {

    /// 校验一个待创建的分支名。
    ///
    /// - Parameter name: **原始输入**，不做任何 trim / 归一化。
    ///   首尾的空格本身就是第 2 条规则（不能含空格）所禁止的 ⇒ 这里判为
    ///   `.containsForbiddenCharacter(" ")`。若调用方希望宽容处理（用户手误多打了空格），
    ///   请**先自行 `trimmingCharacters(in: .whitespacesAndNewlines)` 再调本函数** ——
    ///   本函数不替调用方决定"哪些空白可以忽略"。
    /// - Returns: 第一个不满足的规则；`nil` 表示合法。
    ///
    /// ## 为什么返回"第一个"而不是"全部"
    ///
    /// 提示只显示一句（表单校验的常规做法），而**顺序不是随意的**：
    /// 从"整体形状"到"局部字符"排（空 → 控制字符 → 首尾分隔符 → 连续分隔符 →
    /// 禁字符 → `.lock` → 保留名）。这样 `a b..c` 报的是更根本的 `..`，
    /// 而不是先跳出那个空格 —— 用户一次改一个，报根因的那条更省事。
    public static func validate(_ name: String) -> Issue? {
        if name.isEmpty { return .empty }

        // 控制字符先查：它可能同时"含空格"以外什么都看不出来（`\u{7F}` 在输入框里近乎无形），
        // 若把它排在后面，用户会收到一条解释不了输入内容的提示。
        if name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return .containsControlCharacter
        }

        if name.hasPrefix("/") || name.hasSuffix("/") { return .beginsOrEndsWithSlash }
        if name.hasPrefix(".") || name.hasSuffix(".") { return .beginsOrEndsWithDot }
        if name.contains("//") { return .containsDoubleSlash }
        if name.contains("..") { return .containsDoubleDot }

        // ⚠️ 遍历 `unicodeScalars`（不是 `Character`）—— 见 `forbiddenScalars` 那一段：
        //    按字素簇比会漏掉「禁用字符 + 组合记号」，用户看不出差别、到服务端才吃 422。
        if let scalar = name.unicodeScalars.first(where: { forbiddenScalarSet.contains($0) }) {
            return .containsForbiddenCharacter(Character(scalar))
        }

        // `.lock` 是 git 的索引锁文件后缀：叫 `x.lock` 的分支会让 git 自己撞车。
        if name.hasSuffix(".lock") { return .endsWithLock }

        // 保留名：`HEAD` 是引用记法的名字，不是一条能被创建的分支。
        // ⚠️ 只比**全等**，不做大小写归一 —— `head` 是一条合法且常见的分支名。
        if name == "HEAD" { return .reservedName }

        return nil
    }

    /// 禁止出现的字符（git `check_refname_format` 的字符集 + 空格）—— **有序**。
    ///
    /// 有序是有用的：提示语要按固定次序把它们列出来，而集合拼出来的顺序**每次都不一样**
    /// （那样同一句提示在两次失败里长得不同，看起来像另一条规则）。
    ///
    /// `\` 排在最后 —— 它在 Swift 字面量里要写成 `"\\"`，
    /// 在 git 的文档里写作 `\`，是誊写时最容易丢掉的一个。
    ///
    /// ## ⚠️ 为什么元素类型是 `Unicode.Scalar` 而不是 `Character`
    ///
    /// 判据必须**按标量**比。按 `Character`（= 字素簇）比会漏掉**一整族**写法：
    /// `"~\u{0301}"` 在 Swift 里是**一个**字素簇（`.count == 1`），于是
    /// `name.first(where: { 表.contains($0) })` 那种"逐个 `Character` 查表"拿到的是那一整个簇、
    /// 与表里的 `"~"` 不相等 ⇒ **放行**；可 URL 编码出来是 `~%CC%81`
    /// —— ASCII `~` **原封不动**进了请求 ⇒ git 拒、服务端 **422**。
    /// 而那正是本类型开头写明它存在的那条理由（"某个名字在客户端放行、到服务端吃 422"）。
    ///
    /// - 漏的是**一类**而不是孤例：任何「禁用字符 + 组合记号」都一样（`^` `?` `[` `空格` …）。
    /// - 反证：`"\u{0301}~"`（组合记号在**前**）是两个字素簇、原本就拦得住
    ///   ⇒ 拦不拦只看组合记号写在哪一侧，**而屏幕上两者几乎一样**
    ///   （组合记号无声地依附在前一个字符上）。
    /// - 反向也要防：判据换成标量**不得误伤**。`"～"`（全角 U+FF5E）是**一个**标量 U+FF5E，
    ///   标量序列里**不会**出现 ASCII `~`（全角同形字是独立码位，不是 `~` 的规范分解）
    ///   ⇒ 全角照旧放行（`git check-ref-format` 实测也接受）。
    /// - 想要"分支名只许英文"是**另一个产品口径**，做法是反过来**只放行 ASCII**（白名单），
    ///   不是拉黑同形字 —— 同形码位有几十个，永远拉不完。
    public static let forbiddenScalars: [Unicode.Scalar] = [" ", "~", "^", ":", "?", "*", "[", "\\"]

    /// 判定用的集合视图（`contains` 是 O(1)）。
    ///
    /// 与 `forbiddenScalars` 是**同一份数据的两种形态**（数组保序、集合保快），不是两份清单
    /// —— 这里由它现算，避免"加了禁字符只改一处"的分叉。
    private static let forbiddenScalarSet = Set(forbiddenScalars)

    /// 不合法的原因 —— 每条都对应 `BranchNameCopy` 里一句可显示的话。
    public enum Issue: Equatable, Sendable {

        case empty

        /// 含控制字符（`< 0x20` 或 `0x7F`）—— ⚠️ **有意不带上那个字符本身**：
        /// 它可能就是不可见的，塞进提示里会让那句话看起来"什么都没说"。
        case containsControlCharacter

        /// 含禁止字符 —— 带上**那一个字符本身**（提示里要指名道姓，见 `BranchNameCopy`）。
        ///
        /// ⚠️ 它由命中的 `Unicode.Scalar` 还原而来（**判据按标量、显示按字符**）：
        /// 集合里只有 ASCII，还原出的 `Character` 恒等于那个字符本身。
        case containsForbiddenCharacter(Character)

        case beginsOrEndsWithSlash

        case beginsOrEndsWithDot

        case containsDoubleSlash

        case containsDoubleDot

        case endsWithLock

        /// 保留名（`HEAD`）。
        case reservedName
    }
}

/// 分支名校验失败时的提示文案（PRD §4.8、§7）。
///
/// 与 `SearchCopy` 同源的理由：这是**可见契约**，而"哪一条规则对应哪一句话"
/// 是业务规则不是排版选择。
public enum BranchNameCopy {

    /// 把校验结果翻成一句给用户看的话。
    ///
    /// ⚠️ 每条都写**怎么改**，不只写"不合法"：
    /// 用户手上是一个输入框，他需要的是"把 `..` 去掉"，不是"格式错误"。
    public static func message(for issue: BranchName.Issue) -> String {
        switch issue {
        case .empty:
            "请输入分支名"
        case .containsControlCharacter:
            "分支名不能包含控制字符，请重新输入"
        case let .containsForbiddenCharacter(character):
            // 空格单说一句：否则会拼出"不能包含  与空格…"（那个字符本身是空白，看不见）。
            character == " "
                ? "分支名不能包含空格"
                : "分支名不能包含 \(character)，空格与 \(remaining(BranchName.forbiddenScalars, excluding: character)) 也不允许"
        case .beginsOrEndsWithSlash:
            "分支名不能以 / 开头或结尾"
        case .beginsOrEndsWithDot:
            "分支名不能以 . 开头或结尾"
        case .containsDoubleSlash:
            "分支名不能包含连续的 //"
        case .containsDoubleDot:
            "分支名不能包含连续的 .."
        case .endsWithLock:
            "分支名不能以 .lock 结尾"
        case .reservedName:
            "HEAD 是保留名，不能用作分支名"
        }
    }

    /// 把禁字符列成提示里可读的一串，**排掉已经点名过的那个**。
    ///
    /// ⚠️ 原先这里是一段写死的字符表，命中 `~` 时会印成
    /// 「不能包含 ~、空格，以及 ~ ^ : ? * [ \ 这些字符」—— **`~` 印了两遍**。
    /// 现在改为从 `BranchName.forbiddenScalars` **排掉命中项现算**，
    /// 顺带把"清单存两处"消掉（加禁字符只改一处）。
    ///
    /// ⚠️ 顺序取那个**有序数组**，不能用集合 —— 集合的顺序每次不同，
    /// 同一句提示在两次失败里会长得不一样，看起来像两条不同的规则。
    /// ⚠️ 空格也排掉：它另有自己那一句（"分支名不能包含空格"），
    /// 混进这串里会拼出"空格与  空格"这种说不出话的句子。
    private static func remaining(_ scalars: [Unicode.Scalar], excluding character: Character) -> String {
        scalars
            .map { Character($0) }
            .filter { $0 != character && $0 != " " }
            .map { String($0) }
            .joined(separator: " ")
    }
}
