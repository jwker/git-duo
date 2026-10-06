# AGENTS.md —— GitDuo 2.0 的 AI 开发入口

> 这个文件是**每次动手前必读**的唯一入口：规则、命令、文档索引都在这里。
> 它与 `PRD.md` / `TECH_SPEC.md` 的关系：**规格看文档，纪律看这里**。

## 0. 当前阶段

**切片 1（Auth）已完成 —— 门禁、Keychain、PKCE、刷新、登出全部落地。**
下一步是切片 2（GitHubAPI 客户端骨架）。

| # | 内容 | 状态 |
|---|---|---|
| 1.1 | `KeychainTokenStore`（GitDuoCore）—— 真实 Keychain，替换骨架期内存占位 | ✅（前置条件 **P4 已消解**） |
| 1.2 | `GitHubOAuthClient` / `GitHubAppCredentials`（GitHubAPI）—— 换令牌 / 刷新 / 撤销 | ✅ |
| 1.3 | `OAuthCallback`（GitHubAPI）—— 形状校验 + 一次性 `state` | ✅ |
| 1.4 | `AuthCoordinator`（**GitDuoAuth**，决策 #31）—— 授权编排 + **single-flight** 刷新 | ✅ |
| 1.5 | 登出四步：撤销 → 清 Keychain → 清账号数据 → 重置导航栈 | ✅ ①②④ 落地 + ③ 中**接口缓存**已收口（`AuthCoordinator.signOut` → `HTTPCachePurging`）；③ 其余项待各 Feature 存储就位后接入 |
| 1.6 | 登录段原型断言转 Swift 测试（权限 6 项 + 三项产品承诺） | ✅ |
| 1.7 | 门禁接线：`RootView` 二分 + `LoginFlowView` + `WebAuthenticationSession` | ✅ |

**四包单测 115 项全过**（GitHubAPI 55 · GitDuoAuth 39 · GitDuoCore 14 · GitDuoDesign 7）。

▶ **1.8 真机验收 8/10 已过**（iPhone 17 Pro，自动签名已打通）：真授权 → 令牌落 Keychain →
**杀进程重启仍登录**（Keychain 跨重装持久，实测无 `-34018`）→ 登出回登录页 →
**GitHub 侧那条授权记录真的消失了** → 登出后 `Cache.db` 一条不剩 →
**飞行模式下冷启动仍在主界面**（断网 ≠ 登出）。
⬜ 剩：第 3 步（P2 目视：授权页权限是否 6 条）。
**逐步流程、验收清单、错误对照见 `DEVICE-TESTING.md`**（`make device` 一键：构建 → 安装 → 启动）。
⚠️ **真机上的一条硬经验**：改掉写入路径**不会**清除已经落盘的副本 —— 发现磁盘上有敏感残留时，
除了修写入路径，还要问"**谁负责清它**"（本项目补在 `AuthCoordinator.signOut`）。
⚠️ **同类第二课（同一天，更隐蔽）**：`URLCache` 落盘的**不只是响应体，还有序列化请求对象** ⇒
一个"响应里没有凭据"的请求（`GET /user`）照样把 `Authorization: Bearer ghu_…` 写进 `Cache.db`。
**"响应不含机密"推不出"这个请求可以走系统缓存"**；本包现在**所有出网会话都不挂 `URLCache`**（见 `GitHubURLSession`，决策 #32）。

未落地的界面一律用 `SkeletonScreen` 占位，**没有假数据冒充成品**（登记见 `AppEnvironment.swift`）。

---

## 1. 事实来源与优先级

| 文件 | 视角 | 用途 |
|---|---|---|
| `redesign/prototype/` | **唯一可点验收依据**（入口 `index.html`；`scripts/` 16 个 JS · `styles/` 5 个 CSS） | 交互、文案、布局的最终裁决者 |
| `PRD.md` | 产品 | 行为、文案、边界（**不得出现实现细节**） |
| `TECH_SPEC.md` | 技术 | 架构、API 映射、配额、数据模型、决策表（**32 项全部【已定】**） |
| `REVIEW-CHECKLIST.md` | 评审 + **切片计划正本** | 切片顺序 §1 · 完成定义 §2 · 前置条件 §3 · 断言→切片映射 §4 · **决策记录 D1–D4（已全部拍板）** §5 |
| `GITHUB-APP-SETUP.md` | 运维 | GitHub App 的手把手配置（表单逐栏值、权限 6 项、自检清单、错误码对照） |
| `DEVICE-TESTING.md` | 运维 | 真机测试：一次性准备（含 🔒 无法自动化的一步）、`make device`、1.8 验收清单、错误对照、真机才能验的 5 件事 |

**冲突裁决顺序：原型 > TECH_SPEC > PRD > 任何推测。**
发现三者不一致时：**先报告，不要自行选一个实现**。

⚠️ 原型是**多文件**页面（`redesign/prototype/`）：入口 `index.html` + `styles/` 5 个 CSS + `scripts/` 16 个 JS。
   16 个 JS **共享同一全局作用域，加载顺序即依赖顺序**（无 import/export，const 没有提升）；
   **不要给 script 加 `type="module"`** —— `file://` 下会被 CORS 拦掉，原型就没法双击打开了。
⚠️ 原型有一份 jsdom 回归脚本（**262 条断言**），它记录了历次讨论的结论。
位置：`/Users/jiangjiang/.workbuddy/binaries/node/workspace/harness.js`（在仓库外）。
它是**规格的结晶**，切片落地时按域逐条转成 Swift 测试，不要凭记忆重写行为。

---

## 2. 命令（验证闭环的唯一入口）

```bash
make gen      # xcodegen 生成 GitDuo.xcodeproj（改 project.yml / 增删文件后必跑）
make test     # 四个包的单测（Swift Testing，秒级）
make build    # 为 iOS 模拟器构建 App（不签名）
make verify   # 以上全跑 —— 提交前必跑
make device   # 真机：构建(带签名) → 安装 → 启动 —— 手测用，见 DEVICE-TESTING.md
```

> `make device` 与 `make verify` **互不影响**：前者需要 `Secrets.xcconfig` 里的 `GITDUO_DEVELOPMENT_TEAM`
> 且要设备在线；后者走 `CODE_SIGNING_ALLOWED=NO`，没有签名配置也能跑 ⇒ 保住秒级闭环。

**没有可执行的验证命令的改动，等于没做。** 改完必须给出 `make verify` 的结果。

> ⚠️ **`make build` / `make verify` 必须脱离沙箱且「前台」运行**：`xcodebuild` 解析 SwiftPM 依赖时会内部调用
> `sandbox-exec`，在沙箱里会报 `sandbox-exec: sandbox_apply: Operation not permitted`（看起来像工程坏了，
> 其实是权限）。`swift test` 会写 `~/.cache`，同理。报这个错时**不要改代码**，换非沙箱方式重跑。
>
> 🕳️ **两个更隐蔽的次生坑（2026-10-05 实测踩到）**：
> 1. **放后台执行时沙箱豁免不生效** —— 同样报 `sandbox_apply`，且错误里全是 `swiftc` 的 manifest 编译参数，
>    极易误判成"Swift 包坏了"。**口诀：只要出现 `sandbox_apply: Operation not permitted`，一律是运行环境问题。**
> 2. **`rm -rf <大目录>` 会被安全机制拦截** —— 拦截后 `&&` 短路、**后续命令压根没执行**，
>    而日志文件里还留着上一次的内容 ⇒ 看起来"跑了但没通过"。**别用 `rm -rf` 做 clean**，直接让 xcodebuild 增量构建。

---

## 3. 架构铁律（违反即返工）

```
表现层 Features/  →  领域层 Repository/UseCase  →  数据层 Client/Store
```
- **依赖单向**：数据层不得引用上层类型；领域层**不得出现 SwiftUI 类型**。
- `AppEnvironment` 是**唯一依赖装配点**（`GitDuo/App/AppEnvironment.swift`）。
  View / ViewModel **不得自行构造客户端**。
- 五个 Package 边界（`Packages/`）：`GitHubAPI`（网络 + OAuth **客户端**）· `GitDuoCore`（Keychain 等本地基础设施）·
  `GitDuoAuth`（认证**编排**，依赖前两者 —— **决策 #31**）· `GitDuoDesign`（令牌 + 组件 + 玻璃封装）· App target（组合根 + 页面）。
  `GitDuoDesign` 依赖 `GitDuoCore`，其余互不依赖。
  ⚠️ 编排为什么单独一层：它要**同时**用 `GitHubAPI`（换令牌）与 `GitDuoCore`（写 Keychain），
  而这两包互不依赖 ⇒ 只能在两者**之上**；落在包里而非 App，是为了能跑单测（App 无测试 target）。
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
| 6 | 不用 `UIScreen.main`；布局看 size class 与容器尺寸 | PRD §1：**纯 iPhone，本期不做折叠屏 / iPad** |
| 7 | **只读态显式传参**（`readOnly:`），不让下层页自行推断仓库归属 | §8.2（可写性判定唯一来源 = `Repository.permissions.push`） |
| 8 | 凭据只进 Keychain；**绝不写入**日志 / 崩溃上报 / 剪贴板 / UserDefaults 明文 | §3.3 |
| 9 | `client_secret` **内嵌进 App**（构建期由 `Secrets.xcconfig` 注入，**不入库**）——官方 Required 且无法规避；它是**软机密**，只许出现在「换令牌 / 刷新 / 撤销」三条请求里，**不进日志、不进缓存、不进任何上报** | §3.1 / §3.7（决策 #30） |
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
   给选项与推荐，**不要自定义一个值然后当成事实**（D1–D4 已全部拍板；新的待定点追加到该文件 §5）。
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
| 真机测试 / 手测验收 | `DEVICE-TESTING.md` |
| GitHub App 配置 / 凭据 | `GITHUB-APP-SETUP.md` · `Secrets.xcconfig.example` |

---

## 7. 切片计划 → 见 `REVIEW-CHECKLIST.md`（本节只放指针，不复制）

> **为什么是指针**：切片表原先在本节与 `REVIEW-CHECKLIST.md §1` 各存一份，而**两份都还在改**
> ⇒ 迟早"改一处漏一处"。**正本唯一 = `REVIEW-CHECKLIST.md`**，本节只负责指路。

| 要什么 | 正本位置 |
|---|---|
| 切片顺序、每片内容、对应 PRD 页面、验证方式、可否延后 | `REVIEW-CHECKLIST.md` **§1 清单 A** |
| 每片"做完"的 4 条定义（verify / 断言转测试 / 逐屏对照 / 文档同步） | `REVIEW-CHECKLIST.md` **§2 清单 B** |
| **本期明确不做**的 10 项（**动手前必看，防越界**） | `REVIEW-CHECKLIST.md` **§1 末** |
| 262 断言 → 切片的映射 | `REVIEW-CHECKLIST.md` **§4 清单 D** |
| 前置条件 P1–P6 状态 · 决策记录 D1–D4 | `REVIEW-CHECKLIST.md` **§3 / §5** |

> **排序原则（保留在此，它属于纪律）**：**先做能在本地 100% 验证的纯逻辑，最后做需要真机 / 真凭据的部分。**
> **当前进度**见本文 §0「当前阶段」。
