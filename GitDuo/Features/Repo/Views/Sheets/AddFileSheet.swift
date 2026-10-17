import GitDuoCore
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

    /// 文件名（**不含目录**）—— 落点是"当前打开的那一层目录 + 这个名字"，
    /// 由宿主按 `RepoPath.resolveUpload(directory:fileName:)` 拼出来
    ///（§5.8：上传出口的路径是 App 定的；⚠️ 2026-10-12 之前是恒落仓库根）。
    ///
    /// ⚠️ **转码那一档它已经被换过扩展名**（决策 #72④：`IMG_1234.HEIC` → `IMG_1234.jpg`）——
    /// 这一格收的是 `UploadIntake` 给的**最终**名字，调用点**不要**再自己拼一次原名字
    /// （拼回去的后果是"内容转了、名字没转"，而那正好等于白转：GitHub 按扩展名渲染）。
    let fileName: String

    /// 要写上去的字节。
    ///
    /// ⚠️ **多数情况下它就是相册 / 文件 App 给的那一份原文**（§5.8）；
    /// **两类例外** —— >1MB 的图片被压过（决策 #71）、**网页端显示不出来的格式被转过**
    ///（**决策 #72**，且 **≤1MB 也转**）。"动过什么"由下面那个字段如实带出来。
    let data: Data

    /// "我们动了你选中的东西"的摘要；**`nil` = 一个字节都没动**（≤1MB 且格式显示得出来 / 非图片）。
    ///
    /// ⚠️ 它一路带到提交弹层（`CommitSheet.adjustment`）—— **不能只在这里用掉**：
    /// 用户需要在他按下确认的那一刻看到"要写上去的不是我选的那张原图"。
    let adjustment: UploadAdjustment?
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
/// | `新建文件` | 编辑器（新建模式，§4.6）—— 路径由**编辑器里的输入框**定，弹层只负责说"从哪一层进来的"（宿主把当前目录带去预填） |
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
/// ## ⚠️ 超过 1MB：**图片先压、其余当场拦**（决策 #71）；显示不出来的格式**一律转**（决策 #72）
///
/// 这一档原本只有一句"提示并引导网页端"，而那让**相册这条出口对真实照片形同虚设**
/// （照片动辄好几 MB）。现在两条路：
///
/// | 选中的东西 | 走哪条 |
/// |---|---|
/// | >1MB 的**图片** | 交给 `intake.prepare` → 自适应压缩（`GitDuoCore.ImageProcessor`）→ 压下来就进提交弹层 |
/// | >1MB 的**其他文件** | 当场拦下（`tooLargeHint`）—— 大 PDF / zip 没有"压一道"这回事 |
/// | **压不下来的图片** | 同上：`intake` 回 `.tooLarge` ⇒ 同一句提示 |
/// | **网页端显示不出来的格式**（HEIC / TIFF / BMP / RAW…） | **一律转码 —— ≤1MB 也转**（**决策 #72**）；转完**文件名扩展名跟着换**（`IMG_1234.HEIC` → `IMG_1234.jpg`），提交弹层那行只读落点下会说明动过什么 |
///
/// ⚠️ 拦截点放在**选中那一刻**（而不是等用户在提交弹层里写完信息、按下提交）有两个理由：
/// 用户不必白填一次；而一个 100MB 的文件**根本不会被读进内存**（下面先看 `fileSize` 再读）。
/// ⚠️ 压缩 / 转码要时间（最多 13 次编码）⇒ 有 `isPreparing` 那一档转圈 + 三行暂时不可点。
/// 这一条**不是装饰**：没有它，用户按下去之后会以为弹层死了，然后再点一次。
struct AddFileSheet: View {

    /// 当前分支 —— 标题里那一句要它（原型 `添加文件 · ${curBranch()}`）。
    let branch: String

    /// 取件与预处理（压缩 #71 / 转码 #72）—— 由组合根装配（`AppEnvironment.uploadIntake`）。
    ///
    /// ⚠️ 从外面传进来而不是在这里 `UploadIntake(processor: ImageProcessor())`：
    /// 那会多出一处"App 层知道 `GitDuoCore` 有什么"的装配点（`AGENTS.md §3`）。
    let intake: UploadIntake

    /// 第一行：去编辑器（新建模式）。
    ///
    /// ⚠️ 没有任何参数：**路径由编辑器里的输入框定**（§4.6），不在这里预先算一个。
    let onNewFile: () -> Void

    /// 后两行选中东西之后。宿主据此换成 §5.9 的提交弹层。
    let onPicked: (UploadDraft) -> Void

    @State private var isImportingFile = false
    @State private var isPickingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?

    /// 正在压缩 / 转码（切片 8.7 · 8.8）。见类型说明：这一档必须有动静，且三行要暂时不可点。
    @State private var isPreparing = false

    @State private var failure: String?

    var body: some View {
        // P4：自绘弹层 → 原生 `Form`（`SheetPrimitives` 五件退休，见 `NATIVE-MIGRATION.md` §P4）。
        // 三行动作 → `Form` 内的原生 `Button` 行（leading 图标 + 标题）。
        Form {
            Section {
                // 三行**共用同一个图标**（原型 `openAddSheet` 三行都是 `svg(I.file)`）——
                // 不是"随手复用"：原型就是同一支，改成三个图标会让这一屏与原型不一致。
                Button { onNewFile() } label: { rowLabel(GitHubIcon.file, RepoCopy.newFileAction) }
                    .disabled(isPreparing)

                Button { startPick { isImportingFile = true } } label: { rowLabel(GitHubIcon.file, RepoCopy.uploadFileAction) }
                    .disabled(isPreparing)

                Button { startPick { isPickingPhoto = true } } label: { rowLabel(GitHubIcon.file, RepoCopy.uploadImageAction) }
                    .disabled(isPreparing)
            } header: {
                Text(RepoCopy.addFileSheetTitle(branch: branch))
            }

            // 压缩 / 转码要几百毫秒到一两秒（最多 13 次编码）⇒ 必须有个动静，
            // 否则用户按下去之后会以为弹层死了、然后再点一次。
            //
            // ⚠️ 刻**不加文字**：底部那句已经写着"超过 1MB 的图片会自动压缩 ·
            //    HEIC 等格式会自动转换"，在这里再编一句就是第二处说同一件事
            //   （而那一句要跟着 `maxContentBytes` 与白名单走）。
            if isPreparing {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let failure {
                Section {
                    Text(failure)
                        .foregroundStyle(Theme.Palette.destructive)
                        .multilineTextAlignment(.leading)
                }
            }

            Section {
                Text(RepoCopy.addFileSheetHint)
                    .font(Theme.Font.caption)
            }
        }
        .presentationDetents([.medium])
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
            //    ⚠️ 切片 8.7 之后这条仍然成立（**≤1MB 的图原样上传**），
            //    只在"超过 1MB 且非压不可"时才由**我们自己**压一道（决策 #71）——
            //    让系统先替我们转一次码，只会让那一档多损失一次、而我们连类型都不知道。
            preferredItemEncoding: .current
        )
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await handlePhoto(item) }
        }
    }

    /// 弹层行：leading 图标（18pt 次级色）+ 标题（同 `SheetRow` 几何）。
    private func rowLabel(_ systemImage: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(title)
                .font(Theme.Font.rowTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 三行的动作

    /// 开始一次选择：**先把上一轮的结果清掉**。
    ///
    /// ⚠️ 不清的话，上一轮那句失败提示会一直挂在那儿，而用户此刻正在选下一件东西 ——
    /// 他看到的那句话说的已经不是他手上这件事了（`failure` 必须与"这一次选择"同步）。
    private func startPick(_ begin: () -> Void) {
        failure = nil
        begin()
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
        // 而先进内存一趟。拿不到大小时按"读"处理（"交出结果"那一步还有一次判据兜底）。
        //
        // ⚠️ 但**图片不能在这里就拒**（切片 8.7 / 决策 #71）：它还有"先压一道"那条路。
        //    ⚠️ 而 **≤1MB 的**图片照样不能在这里就放过去（切片 8.8 / 决策 #72）：
        //    它可能是 HEIC，得读进来才知道要不要转。
        //    而"像不像图片"在这一步只能按**扩展名**猜 —— 那是**预检**不是判据
        //   （`UploadIntake.mightBeImage` 的说明：两种猜错里取"宁可多读"那一边）。
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let size, size > intake.targetBytes,
           !UploadIntake.mightBeImage(pathExtension: url.pathExtension) {
            failure = CommitSheetCopy.tooLargeHint
            return
        }

        // ⚠️ `url.lastPathComponent` 就是 §5.8 那个"选中文件的文件名"——
        //    文件 App 这条通道**拿得到**它（相册那条拿不到，见类型说明）。
        do {
            let data = try Data(contentsOf: url)
            // ⚠️ 读**必须在 `defer` 收掉 security scope 之前完成**（就在上一行），
            //    所以这里只把已经到手的字节丢进 `Task` 去做压缩 / 转码那一步。
            Task { await finish(source: .uploadFile, fileName: url.lastPathComponent, data: data) }
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

        await finish(
            source: .uploadImage,
            fileName: UploadFileName.photo(fileExtension: fileExtension, now: Date()),
            data: data
        )
        pickedPhoto = nil
    }

    // MARK: - 交出结果

    /// 两个出口共同的最后一步（**取件预处理** → 交给宿主）。
    ///
    /// ⚠️ `source` 由**入口各自传进来**，不从 `isImportingFile` 反推：
    /// 那个 `Bool` 由系统在选择器关掉时写回 `false`，而回调与它谁先谁后**没有保证**
    /// （反推出来的值会在"两个出口只差一次时序"时错成另一个）。
    private func finish(source: CommitSource, fileName: String, data: Data) async {
        // 压缩 / 转码期间三行已经不可点了，但还有一档能走到这里：系统选择器的回调与那个
        // `Bool` 写回 `false` 的先后没有保证 ⇒ 用户理论上能连点两下。
        // 放行第二次的后果是"同一张图进两次提交弹层"，而进的是**后到的那一次**。
        guard !isPreparing else { return }
        guard !fileName.isEmpty else {
            failure = ActionCopy.failed
            return
        }

        isPreparing = true
        // ⚠️ **"要不要动"那条判据在 `UploadIntake` 里，不在这一层** —— 见那里的说明：
        //    它需要看得见**字节的类型**（≤1MB 的 HEIC 也要转，决策 #72③），
        //    而这里手里只有文件名，扩展名可以是错的。
        let outcome = await intake.prepare(data, fileName: fileName)
        isPreparing = false

        switch outcome {
        case let .accepted(finalName, prepared, adjustment):
            // ⚠️ 用 `intake` 给的 `finalName`，**不是**上面那个入参 ——
            //    转码那一档它已经换过扩展名（决策 #72④），这里拼回原名字就等于白转
            //   （GitHub 按扩展名决定渲染方式）。
            onPicked(UploadDraft(
                source: source,
                fileName: finalName,
                data: prepared,
                adjustment: adjustment
            ))

        case .tooLarge:
            // ⚠️ 几档原因（根本不是图片 / 动图 / 处理不动）给的是**同一句话** ——
            //    用户能做的动作是同一个（去网页端），而"为什么没成"对他没有第二个用处。
            failure = CommitSheetCopy.tooLargeHint
        }
    }
}

#Preview {
    AddFileSheet(
        branch: "feature/auth-refresh",
        intake: UploadIntake(processor: ImageProcessor()),
        onNewFile: {},
        onPicked: { _ in }
    )
    .background(Theme.Palette.background)
}
