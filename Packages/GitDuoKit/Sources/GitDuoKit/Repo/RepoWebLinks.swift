import Foundation

/// `github.com` 上的地址 —— App 里做不了的读 / 写，出口都在这一组函数里。
///
/// ## 为什么值得收成一个类型
///
/// 切片 6.4 落地时"跳网页端"的出口一下长到了三处：
/// 文件查看页的「在 GitHub 上打开」、目录里 `symlink` / `submodule` 那两类条目的出口、
/// 提交详情页的 Revert。三处各自拼字符串的代价不是多几行 ——
/// 而是**拼错了不会报错**：用户看到的是 GitHub 的 404 页，
/// 于是他会以为"这个文件被删了 / 这个提交不见了"，
/// 而真实原因是我们少写了一段引用名（`blob/{ref}/{path}` 里的 `ref`）。
///
/// ## ⚠️ `blob` 而不是 `tree`
///
/// GitHub 对 `blob` 与 `tree` 两个路由的容忍度**不对称**：
/// `blob` 指向目录时会自动跳到目录页，`tree` 指向文件时不会自动跳。
/// 所以统一用 `blob` —— 它在两种情形下都能到对的地方。
///
/// ## ⚠️ 引用名不能省
///
/// `https://github.com/{o}/{r}/blob/{path}` 这种写法在浏览器里能用，
/// 但那是网页端替我们补了一次跳转；直接省掉 `ref` 拼出来的地址在
/// `URL(string:)` 这一步不会失败、也看不出来，只会在打开时落空。
/// 拿不到分支时用字面 `HEAD`（GitHub 认它就是默认分支）。
public enum RepoWebLinks {

    /// 仓库内某个路径在网页端的地址。
    ///
    /// - Parameters:
    ///   - ref: 分支 / 标签 / 提交 SHA。**必传**（调用方拿不到就给 `"HEAD"`）。
    ///   - path: 仓库内路径（`RepoPath.raw`）。
    public static func blob(fullName: String, ref: String, path: RepoPath) -> URL? {
        guard !fullName.isEmpty, !path.raw.isEmpty else { return nil }
        return URL(string: "https://github.com/\(fullName)/blob/\(ref)/\(path.raw)")
    }

    /// 一次提交在网页端的地址。
    ///
    /// ⚠️ 它不是"Revert 的直达地址" —— GitHub 的 revert 是提交页上的一个按钮，
    /// **没有**可以直达它的 URL（`/revert/{sha}` 是 404）。
    /// 这个地址是"用户到了这里就有那个按钮"。
    public static func commit(fullName: String, sha: String) -> URL? {
        guard !fullName.isEmpty, !sha.isEmpty else { return nil }
        return URL(string: "https://github.com/\(fullName)/commit/\(sha)")
    }

    /// 从一个分支到另一个分支的**比较页**（切片 8，「PR 未创建」的出口）。
    ///
    /// ⚠️ **`?expand=1` 不能省**：`compare/{base}...{head}` 本身是"看差异"，
    /// 而带 `expand=1` 才是**直接展开建 PR 的表单**。
    /// 少了它用户到了比较页还得自己找「Create pull request」那颗按钮 ——
    /// 而他刚刚才因为 PR 没建起来被送到这里（§5.9④ 要求的正是"给出口"）。
    ///
    /// ⚠️ 三个点的分隔符是 GitHub 的写法（`base...head`），
    /// 写成两个点会正常返回一个**完全不同**的页面（那是"比较两个提交"），
    /// 不报错、也不明显。
    public static func compare(fullName: String, base: String, head: String) -> URL? {
        guard !fullName.isEmpty, !base.isEmpty, !head.isEmpty else { return nil }
        return URL(string: "https://github.com/\(fullName)/compare/\(base)...\(head)?expand=1")
    }
}
