# AGENTS.md —— GitDuo 2.0 的 AI 开发入口

> 这个文件是**每次动手前必读**的唯一入口：规则、命令、文档索引都在这里。
> 它与 `PRD.md` / `TECH_SPEC.md` 的关系：**规格看文档，纪律看这里**。

## 0. 当前阶段

**骨架已立，尚未开始功能切片。** 仓库里没有假数据冒充成品——
所有未落地的界面都是 `SkeletonScreen`，明确标注"哪个切片落地 + 对应文档章节"。

第一条真代码是 `Packages/GitHubAPI/Sources/GitHubAPI/Auth/PKCE.swift`（RFC 7636 向量已验证）。

---

## 1. 事实来源与优先级

| 文件 | 视角 | 用途 |
|---|---|---|
| `redesign/prototype.html` | **唯一可点验收依据** | 交互、文案、布局的最终裁决者 |
| `PRD.md` | 产品 | 行为、文案、边界（**不得出现实现细节**） |
| `TECH_SPEC.md` | 技术 | 架构、API 映射、配额、数据模型、决策表（**29 项全部【已定】**） |
| `REVIEW-CHECKLIST.md` | 评审 | 范围冻结、前置条件、决策缺口（未拍板项都在这里） |

**冲突裁决顺序：原型 > TECH_SPEC > PRD > 任何推测。**
发现三者不一致时：**先报告，不要自行选一个实现**。

⚠️ 原型有一份 jsdom 回归脚本（260 条断言），它记录了历次讨论的结论。
位置：`/Users/jiangjiang/.workbuddy/binaries/node/workspace/harness.js`（在仓库外）。
它是**规格的结晶**，切片落地时按域逐条转成 Swift 测试，不要凭记忆重写行为。

---

## 2. 命令（验证闭环的唯一入口）

```bash
make gen      # xcodegen 生成 GitDuo.xcodeproj（改 project.yml / 增删文件后必跑）
make test     # 三个包的单测（Swift Testing，秒级）
make build    # 为 iOS 模拟器构建 App（不签名）
make verify   # 以上全跑 —— 提交前必跑
```

**没有可执行的验证命令的改动，等于没做。** 改完必须给出 `make verify` 的结果。

> ⚠️ **`make build` / `make verify` 必须脱离沙箱运行**：`xcodebuild` 解析 SwiftPM 依赖时会内部调用
> `sandbox-exec`，在沙箱里会报 `sandbox-exec: sandbox_apply: Operation not permitted`（看起来像工程坏了，
> 其实是权限）。`swift test` 会写 `~/.cache`，同理。报这个错时**不要改代码**，换非沙箱方式重跑。

---

## 3. 架构铁律（违反即返工）

```
表现层 Features/  →  领域层 Repository/UseCase  →  数据层 Client/Store
```
- **依赖单向**：数据层不得引用上层类型；领域层**不得出现 SwiftUI 类型**。
- `AppEnvironment` 是**唯一依赖装配点**（`GitDuo/App/AppEnvironment.swift`）。
  View / ViewModel **不得自行构造客户端**。
- 四个 Package 边界（`Packages/`）：`GitHubAPI`（网络+认证）· `GitDuoCore`（本地基础设施）·
  `GitDuoDesign`（令牌+组件+玻璃封装）· App target（组合根+页面）。
  `GitDuoDesign` 依赖 `GitDuoCore`，其余互不依赖。
- 四个 Tab **各持一条独立 `NavigationStack`**。路由逻辑一律经 `Router.path(for:)` 按 `selection` 取栈，
  **禁止写死某个 Tab 的栈**（原型阶段因此出过导航错乱）。
- 路由用值类型枚举 `Route` + `navigationDestination(for:)`；
  **禁止** `NavigationLink(destination:)` 闭包式写法（难单测、难程序化导航）。
  `RouteView` 的 switch 必须穷尽——新增 case 忘记接线应当**编译失败**，这是有意的。

---

## 4. 编码铁律

| # | 铁律 | 原因 / 出处 |
|---|---|---|
| 1 | **零第三方依赖**（含测试期尽量自建） | 决策 #12 / §11 |
| 2 | **Swift 6 严格并发**；App 层默认 MainActor，数据层 actor 隔离 | 决策 #9 / §12.1 |
| 3 | 颜色/字号/间距/圆角**一律引用 `Theme` 令牌**，禁写魔法值 | §10.7（为补深色预留，写死色值会导致全量返工） |
| 4 | `.glassEffect` **只允许出现在 `GitDuoDesign` 的组件封装内** | §10.2（玻璃只属导航层；业务代码直接调用必失控） |
| 5 | 玻璃**绝不用在内容层**（列表行、卡片、正文、图片） | §10.2 |
| 6 | 不用 `UIScreen.main`；布局看 size class 与容器尺寸 | 纯 iPhone + 未来可变形态 |
| 7 | **只读态显式传参**（`readOnly:`），不让下层页自行推断仓库归属 | §8.2（可写性判定唯一来源 = `Repository.permissions.push`） |
| 8 | 凭据只进 Keychain；**绝不写入**日志 / 崩溃上报 / 剪贴板 / UserDefaults 明文 | §3.3 |
| 9 | `client_secret` **永不进入客户端**（无后端 + PKCE 的前提） | §3.1 / §3.7 |
| 10 | `code_verifier` 只存内存、**绝不随回调传输**；`state` 一次性 | §3.9（scheme 被抢注时唯一的防线） |
| 11 | "这个能力能不能做"**先查文档结论**（§3.9 / §16 已关闭项），不要凭直觉承诺 | 已核实：置顶无写 API、Revert 无端点、最近访问无 API、通知 API 不支持 App 令牌 |
| 12 | 加任何网络调用前，先看 §13.2 配额预算；GraphQL 单查询 ≤5 点 | 深层嵌套可一次烧掉 100 点 |
| 13 | 长任务/循环里的失败**不要静默吞掉**（尤其 404 与"无权限"被 GitHub 混同） | §14 |

---

## 5. 改动纪律

1. **先文档后代码**：新增/变更行为 → 先改 `PRD.md` + `TECH_SPEC.md`（含决策表与受影响章节）→ 再写代码。
   文档里的决策表是"已定"清单，**增删决策必须同步表末汇总行**。
2. **占位必须登记**：任何以占位（stub）形式存在的类型，登记到 `AppEnvironment.swift`
   底部的 `SkeletonPlaceholders.registry`；删除时一并删除登记项。
3. **文案是契约**：原型里的文案是验收依据；改文案要 grep 全仓（同一句话常散落 4–6 处）。
   行为类文案（承诺"会发生什么"）改完还要**真跑一遍**确认效果兑现得出。
4. **改完必须验证**：`make verify`；无法验证的改动要在回复里明确说"未验证 + 原因"。
5. **不要替用户拍板**：遇到文档未定义的点，写进 `REVIEW-CHECKLIST.md` 的"决策缺口"，
   给选项与推荐，**不要自定义一个值然后当成事实**（当前有 D1/D2/D3 三个待定点）。
6. **提交**：一个切片一个提交；提交信息写"做了什么 + 为什么"，不写"update"。

---

## 6. 文档索引（要做什么 → 看哪一节）

| 要做的事 | 看这里 |
|---|---|
| 认证 / PKCE / 令牌刷新 / 权限 / 回调安全 | TECH_SPEC §3.1–§3.9；PRD §4.0 |
| 端点 ↔ 功能映射 | TECH_SPEC §4.6.x |
| 缓存 / ETag / 分页 | TECH_SPEC §4.4、§7.3 |
| 数据模型 | TECH_SPEC §6.2 |
| 持久化 / 登出清理范围 | TECH_SPEC §7.1、§7.2 |
| 导航 / 路由 / 弹层 / 加载态 | TECH_SPEC §8.1–§8.5 |
| 逐功能技术方案（Auth…Settings） | TECH_SPEC §9.1–§9.15 |
| Liquid Glass 规范与六个坑 | TECH_SPEC §10.1–§10.7 |
| 自研渲染（Markdown / diff / 高亮） | TECH_SPEC §11.1–§11.3 |
| 并发模型 / 测试策略 | TECH_SPEC §12.1、§12.2 |
| 配额与性能预算 | TECH_SPEC §13.2、§13.3 |
| 风险登记表 / 未来工作 | TECH_SPEC §15、§16 |
| 页面与行为（产品口径） | PRD §4（页面）· §5（弹层）· §6（横切） |

---

## 7. 切片顺序（按"可验证性"排，不是按 UI 亲疏排）

> 原则：**先做能在本地 100% 验证的纯逻辑，最后做需要真机/真凭据的部分。**

| 切片 | 内容 | 验证方式 |
|---|---|---|
| 1 | **Auth**（PKCE → 回调 → 换令牌 → Keychain → 刷新 single-flight → 门禁） | 单测（已起步：`PKCETests`）+ 真 GitHub App 手测 |
| 2 | **GitHubAPI 客户端**（REST 骨架 / ETag 三层缓存 / 分页 / 401 刷新 / 限流 / GraphQL `body.errors`） | 单测 + `URLProtocol` 桩件（§12.2） |
| 3 | **仓库列表**（可写性判定 / 分区 / 骨架屏） | 单测 + 模拟器 |
| 4 | **首页 + 探索 + 详情**（置顶只读 / 双榜 / 四分区） | 模拟器 + 原型对齐 |
| 5 | **搜索**（四范围 / 防抖 / Search 配额纪律） | 单测 + 模拟器 |
| 6 | **文件查看 + 提交详情 + 分支管理** | 单测（分支解析规则 §9.4.1）+ 模拟器 |
| 7 | **Issues / PR**（含 diff 解析 §11.2） | 单测（diff 边界）+ 模拟器 |
| 8 | **编辑器与提交**（单文件 ≤1MB，Contents API） | 单测 + 模拟器 |
| 9 | **收藏 / 设置 / 我的 Star** | 单测（计数派生不变式，§9.12） |
| 10 | **收尾**：骨架屏统一、无障碍、性能预算核对 | 全量回归 |

**每一片做完的"完成定义"**：① `make verify` 通过；② 该片涉及的原型断言已转成 Swift 测试并全绿；
③ 与原型逐屏对照无差异；④ 文档已同步（含决策表）。
