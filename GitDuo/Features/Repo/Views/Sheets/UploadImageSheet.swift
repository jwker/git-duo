import GitDuoCore
import GitDuoDesign
import GitDuoKit
import PhotosUI
import SwiftUI
import UIKit

/// 「上传图片」弹层（2026-10-23 定：全局悬浮按钮 → 目标 → 选图 → 提交 → 成功）。
///
/// ## 三屏，但**首屏不出现任何列表**
///
/// | 屏 | 内容 |
/// |---|---|
/// | 首屏 | 目标摘要行（**点它**才去换）+ 图片 + 提交信息 |
/// | 选仓库 | 自己的仓库列表（**只列可写的**）|
/// | 选目录 | 那一层的目录清单（可进下一层 / 回上一层）|
///
/// ## ⚠️ 为什么**不用** `NavigationStack`
///
/// ① 这张弹层是**浮在一条 `NavigationStack` 之上**的 —— 仓库里那条规矩是
///    「`NavigationStack` 全仓只能一个顶层」（嵌套两条栈会被 SwiftUI 并成一条，
///    然后抛 `comparisonTypeMismatch` 崩掉，见 `RepoCodeView` 的类型说明）；
/// ② 这一弹层只有三屏、且是**平级**的 —— 套一条栈会多出一层导航栏，
///    而这三屏的标题各不相同、返回键的行为也不同。
///
/// ⇒ 改成**一个 `Page` 枚举 + 自己画的那一行标题**（见 `header`）。
/// 那行标题与返回键是**自绘**的，但它是**弹层标题栏**，不是内容 —— 与「内容层不许自绘」那条不冲突。
///
/// ## ⚠️ 目标摘要行那一行是**唯一**的入口
///
/// 「换目标」**不是**另一个按钮 —— 就是那一行本身（点它 → 去选仓库）。
/// 另放一个「换目标」链接会在同一屏里出现两个意思相近的可点物。
struct UploadImageSheet: View {

    // MARK: - 依赖（由组合根带下来，页面不 new 用例 —— `AGENTS.md §3`）

    private let repositories: LoadRepositoriesPage
    private let detail: LoadRepoDetail
    private let branches: LoadBranches
    private let treeLoader: LoadRepoTree
    private let saver: SaveFile
    private let intake: UploadIntake
    private let memory: any UploadTargetStore
    private let context: UploadContextStore
    private let toast: ToastCenter

    @State private var model: UploadImageViewModel

    @State private var isPickingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?

    init(
        repositories: LoadRepositoriesPage,
        detail: LoadRepoDetail,
        branches: LoadBranches,
        treeLoader: LoadRepoTree,
        saver: SaveFile,
        intake: UploadIntake,
        memory: any UploadTargetStore,
        context: UploadContextStore,
        toast: ToastCenter
    ) {
        self.repositories = repositories
        self.detail = detail
        self.branches = branches
        self.treeLoader = treeLoader
        self.saver = saver
        self.intake = intake
        self.memory = memory
        self.context = context
        self.toast = toast

        let model = UploadImageViewModel(
            repositories: repositories,
            detail: detail,
            branches: branches,
            tree: treeLoader,
            saver: saver,
            intake: intake,
            memory: memory,
            context: context,
            toast: toast
        )
        _model = State(initialValue: model)
    }

    // MARK: - 主体

    var body: some View {
        Group {
            if let uploadedPath = model.uploadedPath {
                successView(path: uploadedPath)
            } else {
                form
            }
        }
        .background(Theme.Palette.background)
        .task { await model.start() }
        // ⚠️ **成功提示走这里，而不是提交成功的那一刻**（2026-10-23 定的口径）：
        //    成功态留在弹层里（它带着「复制路径」那个动作），
        //    Toast 只在**弹层被划走**时兜底一句 —— 免得一句话说两遍。
        .onDisappear {
            if let target = model.target, model.uploadedPath != nil {
                toast.show(UploadImageCopy.uploadedToast(target: target))
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    // MARK: - 三屏

    @ViewBuilder
    private var form: some View {
        VStack(spacing: 0) {
            header
            Form {
                switch model.page {
                case .main:
                    mainSections
                case .chooseRepository:
                    repositorySection
                case .chooseDirectory:
                    directorySection
                case .chooseBranch:
                    branchSection
                case .newDirectory:
                    newDirectorySection
                }
            }
        }
    }

    /// 标题栏（自绘 —— 见类型说明「为什么不用 `NavigationStack`」）。
    private var header: some View {
        HStack {
            Button {
                if model.page == .main {
                    // 首屏的左边是「取消」⇒ 关掉整张弹层。
                    dismiss()
                } else {
                    // ⚠️ 回**上一页**（页栈）—— 不是直接回首屏：
                    //    从「选分支」退出来应该回到「选目录」那一屏。
                    model.back()
                }
            } label: {
                Text(model.page == .main ? "取消" : "‹ 返回")
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(Theme.Palette.accent)
            }
            Spacer()
            Text(title)
                .font(Theme.Font.rowTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            // ⚠️ 右侧留空（不是 `Text("")`）—— 三屏的右侧动作各不相同，
            //    硬凑一个会得到一个什么都不干的按钮。
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.Palette.surface)
    }

    private var title: String {
        switch model.page {
        case .main: UploadImageCopy.sheetTitle
        case .chooseRepository: UploadImageCopy.chooseRepositoryTitle
        case .chooseDirectory: UploadImageCopy.chooseDirectoryTitle
        case .chooseBranch: UploadImageCopy.chooseBranchTitle
        case .newDirectory: UploadImageCopy.newDirectoryTitle
        }
    }

    // MARK: - 首屏

    @ViewBuilder
    private var mainSections: some View {
        Section {
            targetRow
        } header: {
            Text(UploadImageCopy.targetSectionTitle)
        }

        Section {
            if let draft = model.draft {
                preview(draft)
            } else {
                PhotosPicker(
                    selection: $pickedPhoto,
                    matching: .images,
                    // ⚠️ `.current`（不改编码）—— 重编码会改内容与体积（决策 #71 / #72）。
                    preferredItemEncoding: .current
                ) {
                    // ⚠️ label **就地写**：那个闭包是 `@Sendable` 的，
                    //    引用视图上的一个 MainActor 计算属性会撞隔离规则。
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                        Text("从相册选择")
                            .font(Theme.Font.rowTitle)
                    }
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.l)
                }
            }
            if model.isPreparing {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if let failure = model.preparationFailure {
                Text(failure)
                    .foregroundStyle(Theme.Palette.destructive)
            }
        } header: {
            Text(UploadImageCopy.imageSectionTitle)
        } footer: {
            Text(UploadImageCopy.compressionHint)
        }

        Section {
            TextField("上传图片", text: $model.message)
                .textFieldStyle(.plain)
        } header: {
            Text(UploadImageCopy.commitSectionTitle)
        }

        Section {
            ActionButton(
                title: "上传",
                style: .primary,
                isWorking: model.isSubmitting
            ) {
                Task { await model.submit() }
            }
            .disabled(!model.canSubmit)

            if let failure = model.submitFailure {
                Text(failure)
                    .foregroundStyle(Theme.Palette.destructive)
            }
        }
    }

    /// 目标摘要行 —— **点它去换目标**（不是另一个「换目标」按钮）。
    private var targetRow: some View {
        Button {
            Task { await model.startChoosingRepository() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Palette.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.target?.fullName ?? UploadImageCopy.noTarget)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(model.target.map { targetSummary($0) } ?? UploadImageCopy.noTargetHint)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .disabled(model.isResolving)
    }

    /// 摘要行里的副标题：**目录 + 分支**（相对仓库根）。
    private func targetSummary(_ target: UploadTarget) -> String {
        let directory = target.directory.isRoot ? "/" : target.directory.raw
        return "\(directory) · \(target.branch)"
    }

    /// 已选好的那一张（含"动过什么"的说明 —— 决策 #71 / #72）。
    private func preview(_ draft: UploadDraft) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 44, height: 44)
                .background(Theme.Palette.surfaceSunken, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.fileName)
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let adjustment = draft.adjustment {
                    Text(CommitSheetCopy.adjustmentNotice(adjustment))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(draft.data.count), countStyle: .file))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 选仓库

    @ViewBuilder
    private var repositorySection: some View {
        Section {
            if model.isLoadingRepositories {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(model.repositories) { repository in
                    Button {
                        Task { await model.pickRepository(repository) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text(repository.fullName)
                                .font(Theme.Font.rowTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
            }
            if let failure = model.repositoryFailure {
                Text(failure)
                    .foregroundStyle(Theme.Palette.destructive)
            }
        } header: {
            Text(UploadImageCopy.chooseRepositoryTitle)
        } footer: {
            Text(UploadImageCopy.writableOnlyHint)
        }
    }

    // MARK: - 选目录

    @ViewBuilder
    private var directorySection: some View {
        Section {
            if model.isLoadingDirectories {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if !model.browsingPath.isRoot {
                    Button {
                        Task { await model.browseUp() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text("上一层")
                                .font(Theme.Font.rowTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                ForEach(model.directories) { entry in
                    Button {
                        Task { await model.browse(entry) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text(entry.name)
                                .font(Theme.Font.rowTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
                Button {
                    model.chooseCurrentDirectory()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.Palette.accent)
                        Text(model.browsingPath.isRoot ? "用仓库根" : "就用这一层")
                            .font(Theme.Font.rowTitle)
                            .foregroundStyle(Theme.Palette.accent)
                        Spacer(minLength: 0)
                    }
                }
                // ⚠️ **新建目录**（口径：允许，随文件一起建）。
                Button {
                    model.startNewDirectory()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Text("新目录")
                            .font(Theme.Font.rowTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer(minLength: 0)
                    }
                }
                // ⚠️ **换分支**（口径：默认默认分支，可改）。
                Button {
                    Task { await model.startChoosingBranch() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("分支")
                                .font(Theme.Font.rowTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text(model.target?.branch ?? "")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            if let failure = model.directoryFailure {
                Text(failure)
                    .foregroundStyle(Theme.Palette.destructive)
            }
        } header: {
            Text(model.browsingPath.isRoot
                 ? (model.target?.fullName ?? "")
                 : model.browsingPath.raw)
        } footer: {
            Text(UploadImageCopy.directoryHint)
        }
    }

    // MARK: - 选分支

    @ViewBuilder
    private var branchSection: some View {
        Section {
            if model.isLoadingBranches {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(model.branches) { branch in
                    Button {
                        Task { await model.pickBranch(branch.name) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: branch.name == model.target?.branch
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(branch.name == model.target?.branch
                                                 ? Theme.Palette.accent
                                                 : Theme.Palette.textTertiary)
                            Text(branch.name)
                                .font(Theme.Font.rowTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        } header: {
            Text(UploadImageCopy.chooseBranchTitle)
        }
    }

    // MARK: - 新建目录

    @ViewBuilder
    private var newDirectorySection: some View {
        Section {
            TextField("目录名", text: $model.newDirectoryName)
                .textFieldStyle(.plain)
            if let failure = model.newDirectoryFailure {
                Text(failure)
                    .foregroundStyle(Theme.Palette.destructive)
            }
            ActionButton(title: "用这个目录", style: .primary) {
                model.chooseNewDirectory()
            }
        } header: {
            Text(UploadImageCopy.newDirectoryTitle)
        } footer: {
            Text(UploadImageCopy.newDirectoryHint)
        }
    }

    // MARK: - 成功态

    private func successView(path: String) -> some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.Palette.success)
                Text(UploadImageCopy.successTitle)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                pathBox(path)
                Spacer(minLength: 0)
                ActionButton(title: UploadImageCopy.uploadAnother, style: .ghost) {
                    model.uploadAnother()
                }
                ActionButton(title: UploadImageCopy.done, style: .primary) {
                    dismiss()
                }
            }
            .padding(Theme.Spacing.l)
        }
    }

    /// 成功态里那串路径 + 复制按钮。
    private func pathBox(_ path: String) -> some View {
        HStack(spacing: 10) {
            Text(path)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = path
                toast.show(RepoCopy.pathCopiedToast)
            } label: {
                Text(UploadImageCopy.copyPath)
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.surfaceSunken, in: .rect(cornerRadius: 10))
    }

    // MARK: - 取字节

    /// 取选中那张图的字节 ⇒ 交给模型压缩 / 转码。
    ///
    /// ## ⚠️ 字节在**这一刻**就要拿到手
    ///
    /// `PhotosPickerItem` 依赖进程外的会话（iCloud 那份可能还没下载下来）——
    /// 把它存进状态、下一屏再取，得到的是"读不到字节"且看不出原因。
    ///
    /// ⚠️ 相册那一路**拿不到文件名** ⇒ 自拟（`UploadFileName.photo`，有单测）。
    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            pickedPhoto = nil
            return
        }
        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension
        let fileName = UploadFileName.photo(fileExtension: fileExtension, now: Date())
        await model.prepare(data: data, fileName: fileName)
        // ⚠️ 清掉当前值：否则同一张图再选一次，`onChange` 不会响。
        pickedPhoto = nil
    }

    // MARK: - 关掉弹层

    @Environment(\.dismiss) private var dismiss
}
