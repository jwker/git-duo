import GitDuoDesign
import GitDuoKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 一次上传的原料（§5.8 的两个上传出口）。
///
/// ⚠️ **字节在选中那一刻就已经拿到手了**（而不是把 URL / `PhotosPickerItem` 传下去）：
/// 两个系统选择器给出的东西都是**一次性的**（security-scoped URL 要在回调返回前访问完，
/// `PhotosPickerItem` 依赖进程外的会话）—— 把它们存进 `@State` 再在下一步取，
/// 得到的是"读不到字节"且看不出原因。
struct UploadDraft: Equatable, Sendable {

    /// 这一步从哪个出口来（决定 §5.9 提交弹层的标题）。
    let source: CommitSource

    /// 落在**仓库根**的文件名（§5.8：上传出口的路径是 App 定的）。
    let fileName: String

    /// 原始字节（§5.8：**不重编码** —— 图片取的是相册里那一份）。
    let data: Data
}

/// 添加文件弹层（PRD §5.8、原型 `scripts/15-sheets.js` 的 `openAddSheet`）。
///
/// 结构：标题 `添加文件 · {当前分支}` → 三行（新建文件 / 上传文件 · 文件 App /
/// 上传图片 · 相册）→ 底部说明。
///
/// ## ⚠️ 三个出口从切片 8.4 起**全部可点**
///
/// | 行 | 去向 |
/// |---|---|
/// | `新建文件` | 编辑器（新建模式，§4.6）—— 路径由**编辑器里的输入框**定 |
/// | `上传文件 · 文件 App` | 系统文件选择器 → 提交弹层（§5.9） |
/// | `上传图片 · 相册` | 系统相册选择器 → 提交弹层（§5.9） |
///
/// 前两片的形态（`allowsHitTesting(false)` + 读屏 hint）在 8.4 连同那句 hint
/// （`RepoCopy.addFileUnavailableHint`）一起删掉了 —— 一条"点不动"的说明留在代码里，
/// 会让"这三个出口还不能用"看起来仍然成立。
///
/// ## ⚠️ 两个选择器都**不需要权限声明**
///
/// `.fileImporter` 走系统文件提供者；`PhotosPicker`（`_PhotosUI_SwiftUI` 那一套）
/// 是**进程外**选择器，用户选完只把那一份数据交过来 —— 不读相册权限。
/// 所以 `Info.plist` 里**没有**也不需要 `NSPhotoLibraryUsageDescription`：
/// 申请一个用不到的权限，是一件用户看得见、而我们解释不了的事。
///
/// ## ⚠️ 相册那一条的文件名是**自拟的**（PRD 那条规格在当前 API 下做不到）
///
/// §5.8 写的是"选中图片的文件名"，而 `PhotosPickerItem` 只给
/// `itemIdentifier` / `supportedContentTypes` / `loadTransferable` —— **没有文件名**。
/// 规则落在 `UploadFileName.photo(fileExtension:now:)`（有单测）。
///
/// ## ⚠️ 超过 1MB **在选中那一刻就拦**
///
/// §5.8 要求"提示并引导网页端，**不静默失败**"。拦在这里（而不是等用户在提交弹层里
/// 写完信息、按下提交）有两个理由：用户不必白填一次；而一个 100MB 的文件
/// **根本不会被读进内存**（下面先看 `fileSize` 再读）。
struct AddFileSheet: View {

    /// 当前分支 —— 标题里那一句要它（原型 `添加文件 · ${curBranch()}`）。
    let branch: String

    /// 第一行：去编辑器（新建模式）。
    ///
    /// ⚠️ 没有任何参数：**路径由编辑器里的输入框定**（§4.6），不在这里预先算一个。
    let onNewFile: () -> Void

    /// 后两行选中东西之后。宿主据此换成 §5.9 的提交弹层。
    let onPicked: (UploadDraft) -> Void

    @State private var isImportingFile = false
    @State private var isPickingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(RepoCopy.addFileSheetTitle(branch: branch))

            // 三行**共用同一个图标**（原型 `openAddSheet` 三行都是 `svg(I.file)`）——
            // 不是"随手复用"：原型就是同一支，改成三个图标会让这一屏与原型不一致。
            SheetRow(systemImage: GitHubIcon.file, title: RepoCopy.newFileAction) {
                onNewFile()
            }

            SheetRow(systemImage: GitHubIcon.file, title: RepoCopy.uploadFileAction) {
                isImportingFile = true
            }

            SheetRow(systemImage: GitHubIcon.file, title: RepoCopy.uploadImageAction) {
                isPickingPhoto = true
            }

            if let failure {
                Text(failure)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.destructive)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.top, Theme.Spacing.s)
            }

            SheetHint(RepoCopy.addFileSheetHint)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
        // 两个系统选择器都挂在**行自己**身上：行的动作只置一个 `Bool`，
        // 呈现交给这两个修饰符 —— 行里包一个 `PhotosPicker` 按钮会撞两层样式
        //（它自带按钮外观），而"点击区域与整行不一致"是那种看得出但说不清的瑕疵。
        .fileImporter(
            isPresented: $isImportingFile,
            // `.item` 而不是列一串类型：§5.8 的出口叫「上传文件」，**任何文件**都能传
            //（传不了的那种由服务端与 1MB 那道判据给结果）。
            allowedContentTypes: [.item],
            onCompletion: handleImport
        )
        .photosPicker(
            isPresented: $isPickingPhoto,
            selection: $pickedPhoto,
            matching: .images,
            // ⚠️ `.current`（不改编码）而不是默认的 `.automatic`：§5.8 明写
            //    "相册图片取**原始字节、不重编码** —— 重编码会改内容与体积"。
            preferredItemEncoding: .current
        )
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await handlePhoto(item) }
        }
    }

    // MARK: - 文件 App

    private func handleImport(_ result: Result<URL, any Error>) {
        switch result {
        case let .success(url):
            readImported(url)

        case let .failure(error):
            // ⚠️ **取消不是错误**：`fileImporter` 在用户点「取消」时同样回调 `failure`
            //    （`CocoaError.userCancelled`）。照错误处理会给一句
            //    "操作失败 · 请重试" —— 而他刚刚做的正是"不做了"。
            let nsError = error as NSError
            guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError)
            else { return }
            failure = ActionCopy.failed
        }
    }

    private func readImported(_ url: URL) {
        // ⚠️ `fileImporter` 给的 URL 是 **security-scoped**：不显式开始访问，
        //    `Data(contentsOf:)` 会抛"没有权限"，而那个错误的文案里看不出是权限问题。
        //    成对调用，读完立刻收（`defer` 保证例外路径也收）。
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // 先看大小、再决定读不读 —— 一个 100MB 的文件不该为了"待会儿会被拒绝"
        // 而先进内存一趟。拿不到大小时按"读"处理（下面还有一次按字节数的判据兜底）。
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let size, size > SaveFile.maxContentBytes {
            failure = CommitSheetCopy.tooLargeHint
            return
        }

        // ⚠️ `url.lastPathComponent` 就是 §5.8 那个"选中文件的文件名"——
        //    文件 App 这条通道**拿得到**它（相册那条拿不到，见类型说明）。
        do {
            finish(
                source: .uploadFile,
                fileName: url.lastPathComponent,
                data: try Data(contentsOf: url)
            )
        } catch {
            failure = ActionCopy.failed
        }
    }

    // MARK: - 相册

    private func handlePhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            // iCloud 里那份还没下载下来、或这一项给的表示不是字节 —— 两种都说不出更细的
            // 原因，而用户能做的是"再试一次"。
            failure = ActionCopy.failed
            // 让同一张图可以被再选一次（否则它已经是当前值，`onChange` 不会再响）。
            pickedPhoto = nil
            return
        }

        // ⚠️ 扩展名在**加载之后**读：`preferredItemEncoding: .current` 下服务端可能
        //    给出多种表示，而 `supportedContentTypes` 反映的是**这一次加载**的类型。
        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension

        finish(
            source: .uploadImage,
            fileName: UploadFileName.photo(fileExtension: fileExtension, now: Date()),
            data: data
        )
        pickedPhoto = nil
    }

    // MARK: - 交出结果

    /// 两个出口共同的最后一步（判大小 → 交给宿主）。
    ///
    /// ⚠️ `source` 由**入口各自传进来**，不从 `isImportingFile` 反推：
    /// 那个 `Bool` 由系统在选择器关掉时写回 `false`，而回调与它谁先谁后**没有保证**
    /// （反推出来的值会在"两个出口只差一次时序"时错成另一个）。
    private func finish(source: CommitSource, fileName: String, data: Data) {
        // 与上面那次 `fileSize` 判据是**两条**：相册那条没有 URL 可查大小，
        // 而文件那条的 `fileSize` 也可能取不到。按**真实字节数**再判一次。
        guard data.count <= SaveFile.maxContentBytes else {
            failure = CommitSheetCopy.tooLargeHint
            return
        }
        guard !fileName.isEmpty else {
            failure = ActionCopy.failed
            return
        }
        onPicked(UploadDraft(source: source, fileName: fileName, data: data))
    }
}

#Preview {
    AddFileSheet(branch: "feature/auth-refresh", onNewFile: {}, onPicked: { _ in })
        .background(Theme.Palette.background)
}
