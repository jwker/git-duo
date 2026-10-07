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

        if let forbidden = name.first(where: { forbiddenCharacters.contains($0) }) {
            return .containsForbiddenCharacter(forbidden)
        }

        // `.lock` 是 git 的索引锁文件后缀：叫 `x.lock` 的分支会让 git 自己撞车。
        if name.hasSuffix(".lock") { return .endsWithLock }

        // 保留名：`HEAD` 是引用记法的名字，不是一条能被创建的分支。
        // ⚠️ 只比**全等**，不做大小写归一 —— `head` 是一条合法且常见的分支名。
        if name == "HEAD" { return .reservedName }

        return nil
    }

    /// 禁止出现的字符（git `check_refname_format` 的字符集 + 空格）。
    ///
    /// `\` 是最后一个 —— 它在 Swift 字面量里要写成 `"\\"`，
    /// 在 git 的文档里写作 `\`，容易在誊写时丢掉。
    public static let forbiddenCharacters: Set<Character> = [" ", "~", "^", ":", "?", "*", "[", "\\"]

    /// 不合法的原因 —— 每条都对应 `BranchNameCopy` 里一句可显示的话。
    public enum Issue: Equatable, Sendable {

        case empty

        /// 含控制字符（`< 0x20` 或 `0x7F`）—— ⚠️ **有意不带上那个字符本身**：
        /// 它可能就是不可见的，塞进提示里会让那句话看起来"什么都没说"。
        case containsControlCharacter

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
                : "分支名不能包含 \(character)、空格，以及 ~ ^ : ? * [ \\ 这些字符"
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
}
