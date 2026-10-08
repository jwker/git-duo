import Foundation

/// `PUT /repos/{owner}/{repo}/contents/{path}` 的响应体。
///
/// 官方形状（§4.6.2）：
/// ```json
/// { "content": { "name": …, "path": …, "sha": …, "size": …, … },
///   "commit":  { "sha": …, "message": …, … } }
/// ```
///
/// ## ⚠️ 两个 `sha` 是两件事，别混
///
/// - `content.sha` 是**这个文件的新 blob SHA** —— 下一次更新要拿它当基准（乐观锁）；
/// - `commit.sha` 是**这一次提交的 SHA** —— 真机验收时用它去网页端核对"那次提交真的产生了"。
///
/// 混用的表现是"第二次编辑必然 409"（拿提交 SHA 当文件基准），而那个 409 看起来像
/// 别人在改这个文件。
///
/// ## ⚠️ `content` 是必有的（本类型按官方形状严格解）
///
/// 官方文档与 201 示例都带 `content`，所以这里**不做可选**。
/// 代价说清楚：万一服务端哪天不给了，`PUT` 会**成功**、而解码失败会让调用方
/// 报"提交失败" —— 那是个假话。这一处的取舍是照本包其余全部端点的做法
/// （严格解码、不猜），因为"宽松解码"在这里能猜的东西只有 `nil`，
/// 而 `nil` 又必须被上层处理成"新基准未知"（一圈可选的传播），换不到什么。
/// 真要防它，防的地方是"写操作 2xx 即可判定成功"那条口径，不在这个 DTO 里。
public struct FileWriteResultDTO: Sendable, Equatable, Decodable {

    /// 写入后的文件元数据（`sha` 是新基准，见类型说明）。
    public let content: RepoFileDTO

    /// 这次提交。
    public let commit: Commit

    public struct Commit: Sendable, Equatable, Decodable {

        /// 提交 SHA。
        public let sha: String

        /// 提交信息（服务端回显的那一份 —— 空信息时它会是我们发出去的默认信息）。
        public let message: String?

        public init(sha: String, message: String? = nil) {
            self.sha = sha
            self.message = message
        }
    }

    public init(content: RepoFileDTO, commit: Commit) {
        self.content = content
        self.commit = commit
    }

    /// 新 blob SHA（给 `FileSaveReceipt` 用）。
    public var blobSHA: String { content.sha }

    /// 这次提交的 SHA。
    public var commitSHA: String { commit.sha }
}
