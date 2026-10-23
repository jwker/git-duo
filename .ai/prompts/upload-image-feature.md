# 任务 · 「上传图片到仓库」（悬浮按钮 + 弹层）

> 起档 2026-10-23。**状态：代码已落地（`make verify` 全绿）—— 待真机目视。**
> 提交：`5685b38`（首版）+ `dc347c0`（补分支可改 / 新建目录 / 页栈）。

## 要做的事

悬浮按钮 → 弹层 → 先指定「仓库 + 目录」→ 选图片 → 自动压缩 → 上传 → 提示成功 + 相对路径复制按钮。

## 已定的口径（2026-10-23）

1. 悬浮按钮**全局**：每个页面常驻（首页 / 探索 / 仓库列表 / 搜索 / 仓库页 / 详情页 / 设置页）；
   键盘弹出时收起、文本输入中隐藏。安放点 = `MainTabView` 的 `.overlay(alignment: .bottomTrailing)`（与 `Toast` 同层）。
2. **选型 = 方案 A（56pt 圆形玻璃按钮）+ S3（两段折中）**。最终稿：`.ai/design/upload-image-fab/final-a-s3.html`。
3. 目标**只问一次**：没选过 ⇒ 先选目标；选过 ⇒ 直接进上传。
   ⇒ 「上次目标记忆」是**必需件**（记仓库 + 目录 + 分支），改目标即写回，失效必须回落并提示。
4. 改目标 = **点已选目标那一行** → push 选仓库 / 选目录（复用现成那两层）→ 选完 pop 回来；
   **S3 首屏不出现任何选择列表**。
5. 记忆作默认，页面上**展示已选目标**（仓库名 + 相对目录 + 分支三样写全）。
6. **上下文优先**（已裁）：正站在某个仓库 / 目录里时，默认目标 = 当前仓库 + 当前目录，而非记忆里的那个。
7. 记忆失效**静默回落**（不提示、不报错）；分支**默认取默认分支且可改**；
   复制出去的路径 = **仓库全名 + 仓库内相对路径**（如 `jwker/my-app/assets/photos/x.jpg`）——
   ⚠️ 与现有 `RepoCopy.clipboardPath` 不是一回事，要**新函数**，不要改旧的。
8. 文件名沿用 `UploadFileName.photo`；**允许新建目录**（不存在的目录随文件一起建）；
   成功态 = 弹层不关、整屏换成成功态（含复制按钮）。
   这几条已记入 `.ai/memory.md` §4。

## 口径已齐 —— 下一步就是写代码

顺序建议（每步一个可验证的闭环）：

1. `GitDuoDesign` 加 `FloatingActionButton`（玻璃只许在设计包）→ 单测：尺寸 / 玻璃 / 命中区。
2. `GitDuoKit` 加**目标记忆**（仓库 + 目录 + 分支）+ 失效回落判据（纯函数，有单测）——
   沿用 `BranchMemoryStore` 的套路；再加工一个**带仓库名的路径**函数（不改 `RepoCopy.clipboardPath`）。
3. `MainTabView` 全局 overlay 接上按钮 → 弹层（`UploadImageSheet`）。
4. 弹层：目标摘要行（点那行 push 选仓库 / 选目录）→ 选图（`UploadIntake` 压缩）→ 提交信息 → 上传 → 成功态 + 复制。
5. `make verify` + 真机目视（深色档也要看）。

## 已落地（2026-10-23）

| 件 | 位置 |
|---|---|
| 悬浮按钮 | `Packages/GitDuoDesign/.../FloatingActionButton.swift`（玻璃只许在设计包；macOS 变体有降级路径） |
| 全局入口 | `GitDuo/App/MainTabView.swift` 的 `.overlay(alignment: .bottomTrailing)`（与 Toast 同一层 ⇒ 只有一个实例；键盘弹出时收起） |
| 弹层 | `GitDuo/Features/Repo/Views/Sheets/UploadImageSheet.swift`（三屏 + 两个附加页：选分支 / 新建目录） |
| 状态 | `GitDuo/Features/Repo/ViewModels/UploadImageViewModel.swift` |
| 目标模型与回落 | `Packages/GitDuoKit/.../Files/UploadTarget.swift`（`UploadTargetResolver` 是纯函数） |
| 文案 | `Packages/GitDuoKit/.../Files/UploadImageCopy.swift` |
| 落盘与上下文 | `GitDuo/App/Stores/UploadStores.swift`（`UserDefaultsUploadTargetStore` + `UploadContextStore`） |
| 单测 | `GitDuoKitTests/UploadTargetTests.swift`（9 条）+ `GitDuoTests/UploadTargetStoreTests.swift`（6 条） |

### 顺带做的一件事

`make verify` **接进了 App 层单测**（新增 `make test-app`，T1 计划阶段 3）——
此前 App 层的测试在 `make verify` 里**不会被跑到**（“漏跑”比“跑失败”更危险）。
`AGENTS.md` §1 的命令表与警告同步改了。

## 待目视（只能人眼看，判据 = 用户说"我看了没问题"）

- 悬浮按钮的**位置与遮挡**：右下角会不会压住内容、会不会压住 Tab 栏；
- 玻璃材质在浅色 / 深色两档的观感（深色档 tint 50%）；
- 弹层各屏的观感（首屏 / 选仓库 / 选目录 / 选分支 / 新目录）与自绘标题栏；
- 成功态的路径框与「复制路径」按钮；
- **真机上传一次**（本机无真令牌 ⇒ 之前跑不通）。

## 已知限制（如实记着）

- **选仓库只取第一页**（`GET /user/repos` 的 30 条）—— 可写仓库若在第二页，就选不到它。
- **App 层 ViewModel 没有单测**：`UploadImageViewModel` 的依赖（五个用例 + 两个存储）要在 App 层造齐替身，
  本轮没做；落盘存储那一层已补测。
- **压缩失败提示**沿用 `CommitSheetCopy.tooLargeHint`（与「添加文件」那条出口同一句），
  但那一档的措辞原本是为「文件 App 上传」写的。

## 设计稿（HTML，在 `.ai/design/upload-image-fab/`）

| 文件 | 内容 |
|---|---|
| `final-a-s3.html` | **最终稿**：方案 A + S3 的完整规格（按钮规格 / 目标摘要行 / 记忆写入与失效 / 文案 / 落地清单） |
| `index.html` | 总览、选型记录与待裁定清单 |
| `option-a-circle-fab.html` | 方案 A 提案（已选） |
| `option-b-extended-fab.html` | 方案 B 提案（未采用，存档） |
| `option-c-edge-dock.html` | 方案 C 提案（未采用，存档） |
| `sheet-flows.html` | 弹层内部流程对比：S1 单页 Form / S2 逐级推进 / S3 两段折中 |

## 已确认可复用（不重造）

- 压缩转码：`GitDuoKit.UploadIntake` + `GitDuoCore.ImageProcessor`（≤1MB 且格式可渲染则原样放行）
- 写文件：`GitHubRepoContentEndpoint.putFile`（base64 ⇒ **单文件 ≤1 MB 硬限**）
- 选目录：`LoadRepoTree`；提交信息：`CommitSheet` / `CommitDraft`
- 成功提示：`GitDuoDesign.Toast`（承载不了复制动作 ⇒ 成功态留在弹层内，Toast 只兜底）
- 复制路径：`RepoCopy.clipboardPath` 口径 + `UIPasteboard`

## 硬约束

- 必须先有目标（仓库 + 目录）才有上传动作。
- ≤1 MB 压不下来要明确拦下，不静默截断。
- GitHub `PUT /contents` 不能建空目录 ⇒ 新目录随文件一起产生，文案写「目录（新）」。
- 只列有 push 权限的仓库（铁律 #7）。
- 按钮组件放 `GitDuoDesign/Components/`（铁律 #4：`.glassEffect` 只许出现在设计包）。

## 已定口径汇总（2026-10-23 全部裁完）

1. 悬浮按钮**全局**（每页常驻，键盘弹出时收起）；安放点 = `MainTabView` 的 `.overlay(alignment: .bottomTrailing)`。
2. **方案 A**（56pt 圆形玻璃按钮）+ **S3**（目标摘要行 + 选图/提交同屏）。
3. 目标**只问一次**（记忆作默认）；改目标 = **点已选目标那一行** → push 选仓库 / 选目录 → pop 回来；
   **S3 首屏不出现任何选择列表**。
4. 记忆 = 仓库 + 目录 + 分支；改了就写回；失效**静默回落**。
5. **上下文优先**：站在仓库 / 目录里时，默认目标 = 当前仓库 + 当前目录。
6. 分支默认取默认分支，可改。
7. 复制路径 = **仓库全名 + 仓库内相对路径**；新函数，不改 `RepoCopy.clipboardPath`。
8. 文件名沿用 `UploadFileName.photo`；允许新建目录（随文件一起建）。
9. 成功态：弹层不关、整屏换成功态（含复制按钮）；划走时 Toast 兜底。

待裁定项：**无**。

## 落地时的归属（选型已定）

- `Packages/GitDuoDesign/Components/FloatingActionButton.swift` —— 按钮组件
- `GitDuo/App/MainTabView.swift` —— 全局 overlay（与 `Toast` 同一层）
- `GitDuo/Features/Repo/Views/Sheets/UploadImageSheet.swift` —— 弹层
- 目标记忆 —— 沿用 `BranchMemoryStore` 的套路（记仓库 + 目录 + 分支，带失效兜底）
- 领域层 `GitDuoKit` —— 记忆的读写与失效判据（铁律 #14：规则写纯函数，不写 ViewModel）
