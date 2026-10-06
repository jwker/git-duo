# GitDuo 2.0 技术设计文档

| 项目 | 内容 |
|---|---|
| 产品名称 | GitDuo 2.0 |
| 文档版本 | v1.0 |
| 文档状态 | 待评审 |
| 上游需求 | `PRD.md` v1.0（产品需求，功能唯一依据）、`redesign/prototype/`（交互形态参照，入口 `index.html`） |
| 本文职责 | 把产品需求翻译为可实现的技术方案：技术选型、系统架构、模块划分、数据与网络设计、功能落地方案、实现规范与风险 |

---

## 0. 文档说明

### 0.1 目的与范围

本文档定义 GitDuo 2.0 的技术实现方案，供开发、评审与验收使用。覆盖：技术决策、系统架构、模块划分、认证与权限、网络与 API 映射、缓存与配额、数据模型、持久化、导航架构、逐功能技术方案、UI 实现规范、渲染自研模块、并发模型、测试、性能预算与风险。

**本文不重新定义产品需求。** 功能是什么、交互如何，以 `PRD.md` 为准；本文只回答"怎么实现"。

### 0.2 标记约定

| 标记 | 含义 |
|---|---|
| 【已定】 | 已经拍板的技术决策，后续不再反复 |
| 【待定】 | 受外部平台约束或尚未决策，需要确认后才能开工的项 |

> 本版 **31 项决策全部为【已定】**，无【待定】项。

### 0.3 术语

| 术语 | 定义 |
|---|---|
| **App / 客户端** | GitDuo 2.0 iOS 应用本体 |
| **无后端** | 本产品不自建服务端，所有数据直接来自 GitHub 官方 API |
| **public client** | 运行在用户设备上、无法保护 client_secret 的客户端（本产品即此类） |
| **PKCE** | Proof Key for Code Exchange，公共客户端授权码流程的强制保护机制 |
| **user access token** | 代表用户身份访问 GitHub 的令牌（前缀 `ghu_`） |
| **refresh token** | 用于换发新 user access token 的令牌（前缀 `ghr_`） |
| **条件请求** | 带 `If-None-Match` 的请求，命中 304 时不计入配额 |
| **两个配额桶** | REST 的 `core` 桶与 GraphQL 的 `graphql` 桶，互相独立 |
| **导航层 / 内容层** | Liquid Glass 适用边界的两个层级，详见 §10 |

---

## 1. 技术决策摘要

### 1.1 决策表

| # | 决策项 | 结论 | 状态 |
|---|---|---|---|
| 1 | 客户端技术栈 | **SwiftUI**（原生、声明式） | 【已定】 |
| 2 | 目标平台 | **iOS 27**（Xcode 27 构建）· **纯 iPhone** | 【已定】 |
| 3 | 视觉基线 | **Liquid Glass（液态玻璃）** —— iOS 27 起为默认基线，非可选效果 | 【已定】 |
| 4 | 架构模式 | **分层 + MVVM**：View → ViewModel（`@Observable`）→ Repository → Service → Client | 【已定】 |
| 5 | 认证方式 | **GitHub App + PKCE（user-to-server token）**，无后端 | 【已定】 |
| 6 | 数据来源 | **REST v3 为骨架 + GraphQL v4 补充多路聚合** | 【已定】 |
| 7 | 缓存策略 | **ETag 条件请求 + 内存 LRU + 磁盘持久化** 三层 | 【已定】 |
| 8 | 第三方依赖 | **零运行时第三方依赖**（仅自研模块与系统框架） | 【已定】 |
| 9 | 并发模型 | **Swift 6 严格并发**；App 层默认 MainActor，数据层 actor 隔离 | 【已定】 |
| 10 | 工程组织 | **Swift Package 多模块** + 单一 App target | 【已定】 |
| 11 | 通知能力 | **本期不做**（整体移除：Tab / 角标 / 未读态 / 通知数据模型）。见 §3.5.3 | 【已定】 |
| 12 | 探索趋势取数 | **双榜**：新星榜（`created:` 近期新建 + 高星）/ 活跃榜（`pushed:` 近期有推送），均走 Search API + 本地基线算增幅（见 §9.10.1） | 【已定】 |
| 13 | 交流语言筛选 | **本期不实现**：GitHub 公开 API 无此字段与限定符，仅存在于 Trending 网页；不引入网页抓取（见 §9.10.4） | 【已定】 |
| 14 | 本地持久化 | Keychain（凭据）+ UserDefaults（偏好/小数据）+ 文件缓存（大对象） | 【已定】 |
| 15 | App 标识 | App 名 `GitDuo`；回调 URL scheme **`gitduo://oauth/callback`**；`client_id` 注册时生成并写入 `Secrets.xcconfig`（git-ignored） | 【已定】 |
| 16 | 编辑器提交能力 | **仅单文件**：≤1MB 走 Contents API；不做暂存队列、不做大文件 ⇒ **本期不引入 Git Data API**（见 §9.6） | 【已定】 |
| 17 | Revert 回滚 | **不在客户端实现**（REST 无原生端点）；入口保留，点击跳转 GitHub 网页端（见 §9.7.3） | 【已定】 |
| 18 | 分页交互 | **混合**：普通列表滚动到底自动加载；搜索结果用「加载更多」按钮（Search 配额 10–30/min，见 §4.4） | 【已定】 |
| 19 | 加载态 | 首屏**骨架屏**（尺寸匹配真实布局）· 分页行内加载指示 · 操作按钮内联 loading + 禁用（见 §8.5） | 【已定】 |
| 20 | 深色模式 | **本期不做**；颜色一律走语义 token，不写死色值（为后续补齐预留，见 §10.7） | 【已定】 |
| 21 | 多账号切换 | **本期不做**；本地数据已按 `login` 命名空间预留（见 §7.2） | 【已定】 |
| 22 | 登录 / 授权页 | **未登录全屏门禁**：登录页（品牌 + 6 项权限预告 + GitHub 登录按钮）→ 系统浏览器内 GitHub 授权页（6 条权限清单 + Authorize）→ 回调换令牌 → 进主界面；取消回登录页；退出登录二次确认后回登录页（见 §3.8） | 【已定】 |
| 23 | 首页置顶仓库 | **只读同步 GitHub 个人主页置顶**（GraphQL `ProfileOwner.pinnedItems`，上限 6 个，与网页端一致）；**客户端不提供增删**——官方无置顶 mutation，「管理」跳网页端（见 §4.6.1） | 【已定】 |
| 24 | 收藏夹管理 | **独立管理页**「我的 → 我的收藏」：列表（名称 + 项目数）+ 新建 / 重命名 / 删除；内置「默认收藏夹」带 `isDefault` 标记，**不可重命名 / 不可删除**；**纯本地数据，不发任何请求**（见 §9.12） | 【已定】 |
| 25 | 账号级权限 | **补 `Starring`(RW) 与 `Followers`(RW)**：Star / 取消 Star、Starred 分段、关注 / 取关都依赖它们；两者只作用于"个人关系"，**不授予任何仓库内容的写能力**（见 §3.4） | 【已定】 |
| 26 | 令牌可见范围 | **安装页必须引导选「All repositories（全部仓库）」**：GitHub App 令牌 = 用户权限 ∩ App 权限 ∩ **安装时勾选的仓库**，选部分仓库会让首页 / 仓库列表 / 搜索 / Starred 一起缺数据（见 §3.5.4） | 【已定】 |
| 27 | 授权回调 / URL scheme 安全 | **自定义 scheme 不视为安全边界**：PKCE + 一次性 `state` + 回调只带 `code`/`state`（**绝不带令牌**）+ 拒绝静默授权 + scheme 不承载深链；抢注 / 劫持的四类场景与残余风险已登记，收敛方向为 claimed HTTPS（Universal Link）（见 §3.9） | 【已定】 |
| 28 | 当前分支的作用域 | **按仓库分别记忆的会话状态**（`RepositoryScope.branch(for:)`），不是全局唯一值；进入仓库时记忆失效则**回落 `defaultBranch`**（见 §9.4.1） | 【已定】 |
| 29 | 收藏夹项目数 | **由归属映射推导**，不做独立计数器；换列表 = 源夹 −1 且目标夹 +1，删除夹时其中的项回落默认夹（见 §9.12） | 【已定】 |
| 30 | 客户端凭据与 PKCE 的关系 | **叠加，不是二选一**（用户 2026-10-05 拍板）：GitHub 明确「**不区分** public / confidential client」，换令牌与刷新都把 `client_secret` 标为 **Required** ⇒ **不存在"用 PKCE 换掉 secret"这条路**；官方对 public client 的建议本身就是"把 secret 打进包里 **+** 用 PKCE"。故本项目**内嵌 `client_secret`（软机密）并叠加 PKCE**。附带解锁：既然 secret 已在手（可做 Basic Auth）⇒ **登出可程序化撤销 GitHub 侧授权**（`DELETE /applications/{client_id}/grant`），消解了"文案已承诺撤销授权、实现却做不到"的旧矛盾 | 【已定】 |
| 31 | 认证编排的落点 | **独立 `GitDuoAuth` Package**（用户 2026-10-06 拍板）：编排必须**同时**用 `GitHubAPI`（换令牌 / 刷新 / 撤销）与 `GitDuoCore`（Keychain 落盘），而这两包按依赖铁律**互不依赖** ⇒ 编排只能位于两者**之上**。落在包里而非 App target，是为了跟着 `make test` 跑**秒级单测**（App target 无测试 target）；App 层只剩 `ASWebAuthenticationSession` 胶水（系统 API，无逻辑可测）。代价：包拓扑 4→5（见 §2.2 / §3.1） | 【已定】 |
| 32 | API 流量走不走系统 `URLCache` | **不走**（2026-10-06 真机实测后定）：`URLCache` 落盘的**不只是响应体，还有序列化后的请求对象** —— 设备 `Cache.db` 的 `cfurl_cache_blob_data.proto_props` 里明文躺着 `Authorization: Bearer ghu_…` 与 `_octo` Cookie（响应体是干净的，**泄露源是请求头**）。故本包**全部出网会话**统一走 `GitHubURLSession.noCache()`（`urlCache = nil` + 无 Cookie 罐）；§5.1 的 L2 / L3 缓存**自建**（只存 URL / ETag / 响应体 / 过期时间），**不回头启用系统缓存** | 【已定】 |

> **状态汇总**：32 项决策 **全部【已定】**，无【拟定】、无【待定】项。**产品侧与技术侧的开放问题已全部清零**（见 §16），可以进入工程搭建。

### 1.2 三条"不可动摇"的约束

这三条由外部平台决定，不是设计偏好，全篇方案都建立在它们之上：

1. **无后端 ⇒ 必须 PKCE，且 `client_secret` 只能内嵌（无法保密）。** 官方明文：公共客户端**无法保护** `client_secret`，应使用 PKCE(S256)；但 GitHub **不区分 public / confidential 客户端**，换令牌时 `client_secret` 标为 **Required** ⇒ **PKCE 不能替代 secret，secret 也无法保密**，二者是叠加而非二选一（决策 #30，见 §3.7）。同时意味着**绝不能**把 GitHub 令牌递给任何自有服务换凭证（本产品无自有服务，此风险天然不存在）。
2. **通知 API 只认 classic PAT。** `GET /notifications` 全系列官方写明 `only support authentication using a personal access token (classic)`，且明确不适用于 GitHub App 用户令牌、安装令牌、细粒度 PAT。这与决策 5 直接冲突，是本项目唯一的"平台级矛盾"。**本项目已据此决策：通知能力本期整体不做**（见 §3.5.3），矛盾随之规避。
3. **配额是两个独立桶，且条件请求免费。** REST 5000 请求/小时、GraphQL 5000 点/小时互不消耗；REST 的 ETag 命中 304 不计限额。这决定了下文缓存策略不是"优化"，而是预算的一部分。

### 1.3 为什么选 GitHub App 而不是 OAuth App

| 维度 | OAuth App + classic 体系 | GitHub App |
|---|---|---|
| 官方定位 | classic / legacy，**无弃用时间表** | **官方明确推荐并推动迁移的方向** |
| 权限粒度 | 账号级 + 资源包级（`repo` 一包全含），无法限定仓库 | 仓库级可选 + 每类资源独立开关 |
| 令牌形态 | 长效 | 1 小时（安装令牌）/ 8 小时（用户令牌）+ 6 个月刷新 |
| 撤销 | 用户在设置页手动撤销 | **App 可程序化撤销**（`DELETE /applications/{client_id}/grant`，Basic Auth 用 client_id + secret，对 `ghu_` 令牌同样适用）；卸载即全局失效 |
| 安装体验 | 一步授权 | 需安装；⚠️ GitHub 提供的 "Request user authorization during installation" 虽可合并两步，**但会绕过 `state` 与 PKCE 并锁定第一个回调 URL**（§3.9 的防护依赖二者）⇒ **本项目不勾**，安装与授权分两步（见 `GITHUB-APP-SETUP.md` §0.2） |
| 迁移成本 | 未来需再迁一次 | 无 |

**核心理由是时机**：本项目正在重做工程，历史遗留的"未来迁移到 GitHub App"包袱自动清零，迁移成本为零。现在选 OAuth App 等于主动预定一次未来迁移。

---

## 2. 系统架构

### 2.1 总体分层

产品**没有自建后端**，客户端直接与 GitHub 官方 API 通信。分层如下：

```
┌───────────────────────────────────────────────────────────────┐
│  表现层 Presentation                                          │
│  SwiftUI Views · @Observable ViewModels · 导航栈 · 设计系统   │
│  —— Liquid Glass 只出现在这一层的「导航层」（§10）           │
└───────────────────────────┬───────────────────────────────────┘
                            │ 只依赖领域层，不直接触碰网络
┌───────────────────────────▼───────────────────────────────────┐
│  领域层 Domain                                                │
│  Repository（仓储） · UseCase（业务动作） · Domain Model      │
│  —— 权限判定 / 收藏语义 / 提交链路 / 搜索编排 都在这里       │
└───────────────────────────┬───────────────────────────────────┘
                            │
┌───────────────────────────▼───────────────────────────────────┐
│  数据层 Data                                                  │
│  GitHubRESTClient · GitHubGraphQLClient · DTO · 分页          │
│  CacheStore(内存/磁盘) · Keychain · 本地存储 · 限流器         │
└───────────────────────────┬───────────────────────────────────┘
                            │ HTTPS
┌───────────────────────────▼───────────────────────────────────┐
│  外部：GitHub REST v3  /  GitHub GraphQL v4  /  OAuth 授权页  │
└───────────────────────────────────────────────────────────────┘
```

**依赖方向铁律**：表现层 → 领域层 → 数据层，**单向**。数据层不得反向引用上层的任何类型；领域层不得出现 SwiftUI 类型。

### 2.2 模块划分

采用 Swift Package 多模块，按"可变性"与"可测试性"切分：

| 模块 | 类型 | 职责 | 依赖 |
|---|---|---|---|
| `GitHubAPI` | Package | REST / GraphQL 客户端、DTO、分页、ETag 缓存、限流、错误模型、OAuth **客户端**（授权 URL / 换令牌 / 刷新 / 撤销） | 无（仅 Foundation） |
| `GitDuoCore` | Package | Keychain、本地持久化、Markdown 渲染、unidiff 解析、语法高亮、格式化、日期 | 无 |
| `GitDuoAuth` | Package | 认证**编排**：PKCE 材料生成与暂存、回调校验、换令牌、写 Keychain、single-flight 刷新、登出撤销（决策 #31） | GitHubAPI + GitDuoCore |
| `GitDuoDesign` | Package | 设计令牌（色/字/间距）、通用组件、Liquid Glass 封装（`GlassButton` / `GlassChip` / `GlassBar`） | GitDuoCore |
| `GitDuo` | App target | 组合根 `AppEnvironment`、App 入口、路由注册、各 Feature 页面与 ViewModel | 以上全部 |

**为什么这样切**：`GitHubAPI` 与 `GitDuoCore` 完全不依赖 UI，可独立跑单元测试、可被未来其他 target（如 Widget）复用；`GitDuoDesign` 把玻璃用法收敛到一处，避免"随手加玻璃"失控（这是本项目最易犯的错，见 §10）。

**为什么编排要单独一层（决策 #31）**：它必须**同时**看见两边——换令牌只有 `GitHubAPI` 有、写 Keychain 只有 `GitDuoCore` 有，而这两包**互不依赖**。于是"同时看见两边"的逻辑只能待在它们**上面**，正如 App 层一直以来的位置；区别是它不碰 UI，因此**能跑单测**。若把它塞进 App target，这段最需要被验证的逻辑（`state` 校验、单飞刷新、登出降级）就会落进一个没有测试 target 的地方。

**Feature 内部分层**（`GitDuo/Features/<Name>/`）：

```
Features/Repos/
├── Views/          RepoListView · RepoDetailView · FileView · EditorView …
├── ViewModels/     RepoListViewModel · RepoDetailViewModel …
└── Components/     该 Feature 私有子组件
```

### 2.3 目录结构（拟定）

```
my-git/
├── PRD.md
├── TECH_SPEC.md
├── project.yml                     # xcodegen 工程描述
├── Secrets.xcconfig                # client_id 等（git-ignored）
├── Packages/
│   ├── GitHubAPI/
│   │   └── Sources/GitHubAPI/{REST,GraphQL,Auth,DTO,Cache,Pagination}
│   ├── GitDuoCore/
│   │   └── Sources/GitDuoCore/{Keychain,Store,Markdown,Diff,Highlight,Format}
│   ├── GitDuoAuth/
│   │   └── Sources/GitDuoAuth/          # 认证编排（决策 #31）
│   └── GitDuoDesign/
│       └── Sources/GitDuoDesign/{Tokens,Components,Glass}
└── GitDuo/
    ├── App/            GitDuoApp.swift · AppEnvironment.swift · RootView.swift
    ├── Navigation/      Router · Route · 各 Tab 栈
    ├── Features/{Home,Search,Repos,RepoDetail,Issues,PullRequests,
    │             Explore,Notifications,Profile,Stars,Settings}
    └── Resources/       Assets.xcassets · Localizable
```

### 2.4 组合根

`AppEnvironment` 是唯一的依赖装配点，持有：`AuthCoordinator`（认证编排，决策 #31）、`GitHubRESTClient`、`GitHubGraphQLClient`、`CacheStore`、`LocalStore`、各 Repository。通过 SwiftUI Environment 注入，**不在 View 内直接构造客户端**。

---

## 3. 认证与凭据管理

### 3.1 授权流程（PKCE · 授权码模式）

| 步骤 | 动作 |
|---|---|
| 1 | App 生成 `code_verifier`（高熵随机串）→ 计算 `code_challenge = BASE64URL(SHA256(verifier))` |
| 2 | 生成随机 `state`（防 CSRF），与 verifier 一并暂存于内存 |
| 3 | 用 `ASWebAuthenticationSession` 打开 `https://github.com/login/oauth/authorize?client_id=…&redirect_uri=gitduo://oauth/callback&state=…&code_challenge=…&code_challenge_method=S256` |
| 4 | 用户在系统浏览器视图内完成授权（**不用 WKWebView**，防钓鱼且可复用已有登录态） |
| 5 | 回调带回 `code` 与 `state`；App **校验 state 一致**后继续 |
| 6 | `POST https://github.com/login/oauth/access_token`，携带 `client_id`、**`client_secret`**、`code`、`redirect_uri`、`code_verifier`（secret 为官方 **Required**，无法省略——见 §3.7 / 决策 #30） |
| 7 | 得到 `access_token`(`ghu_`)、`refresh_token`(`ghr_`)、`expires_in`(28800)、`refresh_token_expires_in`(15897600) |
| 8 | 立即校验令牌有效性（`GET /user`），成功后写入 Keychain，进入主界面 |

**要点**
- 【已定】走 PKCE 授权码流程，**不启用 device flow**（官方明确反对：设备码不需 redirect URI，易被钓鱼冒充 App）。
- 【已定 · 决策 #30】**`client_secret` 内嵌进 App**：GitHub 换令牌**强制要求**它，且官方不区分 public / confidential 客户端（**不存在"用 PKCE 换掉 secret"这条路**），官方对 native app 的建议正是"打进包里 + 用 PKCE"。因此本项目的定位是：**secret 属"软机密"**（挡得住随手 curl 调接口，**挡不住反编译**），**PKCE + 一次性 `state` 才是真正的防线**，不因持有 secret 而放松（§3.9）。它只出现在「换令牌 / 刷新 / 撤销」三条请求里，不进日志与崩溃上报（§14）。
- 【已定】首次兑换令牌时可携带 `repository_id` 参数，把该令牌的可访问范围**进一步收窄到单个仓库**（GitHub App 独有能力，OAuth App 做不到）——预留给未来的"单仓库工作模式"。
- 【已定】走用户授权路线**不需要 App 私钥**（私钥仅用于"以 App 自身身份"签发安装令牌，本项目用不到）。
- 【已定 · 决策 #31】**编排落在独立的 `GitDuoAuth` 包**（`AuthCoordinator`，`actor`）：步骤 5–8 的串联、single-flight 刷新、登出撤销都在那里；`GitHubAPI` 只管"发哪个请求"，`GitDuoCore` 只管"存哪里"。App 层仅保留 `ASWebAuthenticationSession` 的胶水封装（系统 API，无逻辑可测）与界面。
- 【已定】**URL scheme 不是安全边界**：自定义 scheme 可能被其他 App 抢注、回调可能被劫持。防御依赖 **PKCE + 一次性 `state`**，而非"只有本 App 能收到回调"这一假设；四类风险场景、已采纳缓解与残余风险见 §3.9。

### 3.2 令牌生命周期与刷新

| 令牌 | 有效期 | 处理 |
|---|---|---|
| `access_token` (`ghu_`) | **固定 8 小时** | 内存持有，过期前静默刷新 |
| `refresh_token` (`ghr_`) | **6 个月** | 仅存 Keychain，绝不进内存之外的日志/崩溃上报 |

刷新策略【已定】：
1. 记录 `accessTokenExpiry`；**过期前 5 分钟**触发后台预刷新（`grant_type=refresh_token`）。⚠️ 刷新请求**同样必须携带 `client_secret`**——官方参数表写明 "Required **unless** the user access token was generated using the device flow"，本项目不走 device flow（决策 #30）。
2. 任一请求收到 **401** ⇒ 立即尝试刷新一次 ⇒ 成功则**重放原请求**（仅重放一次，防死循环）。
3. 刷新失败（refresh token 失效/被撤销）⇒ 清除凭据、置为未认证、跳转授权页，并提示"登录已过期，请重新授权"。
4. 刷新请求本身要做 **single-flight**（actor 内串行 + 结果共享），避免并发 401 触发多次刷新导致 refresh token 轮换竞争。

### 3.3 凭据存储

- 【已定】`access_token` / `refresh_token` 存 **Keychain**，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（不进 iCloud 备份、不跨设备迁移）。
- App 元数据（过期时间、账号登录名、App 安装标识）存 Keychain 附属条目或 UserDefaults（非敏感）。
- ⚠️ 凭据**绝不写入**：日志、崩溃上报、剪贴板、UserDefaults 明文、任何磁盘缓存目录。
- ⚠️ **令牌请求必须走「不挂 `URLCache` 的会话」**（2026-10-06 真机实测补齐）：`URLSession.shared` 默认带磁盘缓存，会把**换令牌响应**（含 `access_token` / `refresh_token`）写进 `Library/Caches/<bundle-id>/Cache.db` —— 与上一条直接冲突（真机上取回该文件已确认）。
- ⚠️⚠️ **同一个坑还有第二层，且更隐蔽：`URLCache` 连「序列化后的请求对象」一起落盘**（2026-10-06 真机二次实测，决策 #32）。
  设备 `Cache.db` 的 `cfurl_cache_blob_data.proto_props` 里明文躺着 `Authorization` + `Bearer` + `ghu_…`，外加 GitHub 的 `_octo` Cookie。
  **响应体是干净的（`/user` 只返回公开资料），泄露源是请求头** —— 也就是说"响应不含机密"**推不出**"这个请求可以走系统缓存"。
- ⚠️ **结论：本项目所有出网会话都不挂 `URLCache`**（不只令牌请求）。落点 = `GitHubURLSession.noCache()`（`urlCache = nil` + `requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData` + 无 Cookie 罐），
  令牌客户端与 `GET /user` 共用这一份配置；`GitHubURLSessionTests` 四条断言守住（含"默认会话不落盘"）。
  ⚠️ 别用"给请求设 `cachePolicy`"代替：那个字段描述的是**取用时**是否走缓存，挡不住**存**。

### 3.4 权限清单

| 资源 / 账号权限 | 权限 | 用途 |
|---|---|---|
| Metadata | Read（必需） | 所有 API 的基础 |
| Contents | **Read & Write** | 读：代码 / 文件树 / README / 分支浏览；写：新建 / 上传 / 编辑文件、提交（`PUT /contents`）、建分支 |
| Issues | Read & Write | Issue 列表 / 详情 / 新建 / 关闭 / 评论 / 标签 |
| Pull requests | Read & Write | PR 列表 / 详情 / 评论 / 合并 / 关闭 |
| **Starring**（账号级） | Read & Write | `PUT`/`DELETE /user/starred/{owner}/{repo}`；`GET /user/starred`（Starred 分段、「我的 Star」页） |
| **Followers**（账号级） | Read & Write | `PUT`/`DELETE /user/following/{username}`（用户资料页的关注 / 取关） |

- 【已定】只勾这六项，其余全部不勾，最大化用户信任。
- ⚠️ **Contents 必须为 Read & Write**：编辑器「保存即一次提交」走 `PUT /repos/{o}/{r}/contents/{path}`，只读权限下该请求会直接 403。授权的 Read 权限不构成"只能读不能写"的产品限制——**能否写入具体某个仓库**由 §3.5 的能力边界与仓库权限位另行判定，与 App 声明的权限是两回事。
- ⚠️ **Star 与关注必须补 `Starring` / `Followers`**（2026-10-05 核实）：这两个端点**支持 GitHub App 用户访问令牌**，但要求对应的账号级（Account）权限——缺了会直接 403，且 `GET /user/starred` 在无该权限时**只返回公开部分**（私有 Star 的仓库静默缺失）。二者均为**账号级权限**，只改变"你与仓库 / 用户的个人关系"，**不授予对任何仓库代码的写能力**。
- 这六项必须与**登录页的权限预告**、**GitHub 授权页的权限清单**逐条对应（同一数据源渲染，见 §3.8）。
- 【已定】GitHub App 用户令牌的 `scope` 字段**恒为空串**——实际权限 = **App 声明权限 ∩ 用户自身权限 ∩ 安装仓库范围**，App 不可能越权。客户端不得依赖 `scope` 字段做能力判断，应以"App 声明的权限 + 实际 API 返回码"判断。

### 3.5 能力边界（重点）

#### 3.5.1 完全支持的能力

仓库浏览、文件读写与提交、分支管理与合并、Issue 全流程、PR 全流程（含三种合并方式）、**Star / 取消 Star**（需 `Starring` 账号级权限）、**关注 / 取关**（需 `Followers` 账号级权限）、Fork、搜索（仓库/用户/代码/Issue·PR）、贡献热力图（GraphQL）、语言构成、贡献者、Release 信息。

#### 3.5.2 需要额外确认的能力

| 能力 | 问题 | 处置 |
|---|---|---|
| **Watch（订阅）** | 订阅端点（`PUT /repos/{owner}/{repo}/subscription`）在 classic 体系下属于 `notifications` 权限域，与通知同源 | 【已定】**本期仅展示 Watch 数，不实现订阅动作**——订阅的唯一产出是通知，通知本期不做，订阅遂无意义。该端点本期不请求，也不再需要实测 |

#### 3.5.3 通知能力【已决策：本期不做】

**结论：通知能力本期整体不做。** 底部 Tab 由 5 个减为 **4 个**（首页 / 仓库 / 探索 / 我的），PRD 已同步修订（§2.2、§4.16）。

**决策依据**（此前分析的三条路线，最终选 C）：

| 路线 | 做法 | 结论 |
|---|---|---|
| A. 通知 Tab 降级 | 保留 Tab，用「订阅动态聚合」近似 | 未采纳：语义不等价（缺 `reason`、缺已读态、可能重复），且要额外维护一套聚合管线 |
| B. classic PAT 补偿 | 用户主动粘贴仅含 `notifications` 的 classic PAT | 未采纳：需引入第二套凭据与生命周期管理；官方明确"不应把 PAT 作为 App 认证方式" |
| **C. 本期不做** | 移除通知能力与 Tab | **✅ 采纳。** 规避了唯一的平台级矛盾（约束 2），凭据模型保持单一，工程范围收敛 |

**移除范围**（本期不实现、也不预留）：
- 通知 Tab、未读角标、单条 / 全部已读状态机、通知类型图标、通知数据模型（`Notification`）。
- `GET /notifications` 全系列端点与 `X-Poll-Interval` 轮询逻辑。
- Watch 订阅动作（见 §3.5.2）。

**后续恢复成本**（如未来重启）：若届时 GitHub 将通知端点开放给细粒度令牌或 GitHub App 令牌，只需新增一个数据源实现即可，不牵动现有任何层——本决策**不产生技术债**。

#### 3.5.4 令牌可见范围（GitHub App 特有约束）⚠️

GitHub App 的用户访问令牌（`ghu_`）的可见范围是**三重交集**：

> **用户自身可访问的资源　∩　App 声明的权限　∩　安装时勾选的仓库**

官方原文（《为 GitHub 应用生成用户访问令牌》）：*「若应用获准访问仓库 A 与 B，而用户能够访问仓库 B 与 C，则用户访问令牌只能访问仓库 B，而无法访问 A 或 C。」*

**影响面**（用户若在安装页选了「Only select repositories」）：

| 页面 / 能力 | 表现 |
|---|---|
| 首页（置顶卡片、最近访问跳转） | 未勾选的仓库打不开（403 / 404） |
| 仓库列表（全部 / 公开 / 私有 / Starred） | 只列出被勾选的那部分 |
| 搜索（仓库 / 代码 / Issue·PR） | 结果按令牌可见范围静默过滤，数量变少 |
| 我的 Star / Starred 分段 | 同上，缺私有 Star 的仓库 |

**处置**【已定】：
- **安装页必须引导用户选择「All repositories（全部仓库）」**——引导文案写在**登录页安全说明**中（PRD §4.0.1），与权限预告同屏，用户点「使用 GitHub 登录」前即可看到。
- ⚠️ 该约束**为 GitHub App 独有**，OAuth App 无此限制；但 OAuth App 无法提供细粒度权限，且两条路都必须走 PKCE（§3.1），故不构成改回 OAuth App 的理由。
- **检测手段（技术储备，本期不做 UI）**：`GET /user/installations` → `GET /user/installations/{installation_id}/repositories` 可列出令牌实际可访问的仓库，将来可用于「授权范围自查」入口。
- 失败表现须有兜底：仓库详情 / 文件页拿到 403 / 404 时，文案要指向"可能是授权范围不包含该仓库"，而不是笼统的"网络错误"。

### 3.6 登出与授权撤销

【已定】
- **登出 = 四步**：① **撤销 GitHub 侧授权** → ② 清除本地全部凭据（Keychain）→ ③ 清空与该账号绑定的本地数据（最近访问、收藏夹与归属映射、搜索历史、**按仓库的分支记忆**、接口与图片缓存）→ ④ 重置全部 `NavigationStack` 与 Tab 选中项。
- ⚠️ **③ 的落点分两处**（决策 #31 之后追认）：**"接口缓存"由认证编排层收口** —— `AuthCoordinator.signOut()` → `HTTPCachePurging`（`GitDuoCore`）。
  理由：它不属于任何 Feature，却是**唯一可能把凭据留在磁盘上的东西**。真机实测（2026-10-06）：换令牌响应一度被写进
  `Library/Caches/<bundle-id>/Cache.db`；而**改掉写入路径只能阻止将来再写，已落盘的副本只有显式清理才会消失**。
  其余各项（最近访问 / 收藏夹 / 搜索历史 / 分支记忆）仍按原计划随各 Feature 落地时接入 App 层的 ③。
- **撤销端点**（决策 #30 解锁的能力）：`DELETE /applications/{client_id}/grant`
  —— **Basic Auth 用 `client_id` : `client_secret`**，body 传 `access_token`，成功返回 **204**。官方明确该组端点**同时适用于 OAuth App（`gho_`）与 GitHub App 用户令牌（`ghu_`）**：
  > Tokens for OAuth apps have the prefix `gho_`, while OAuth tokens for GitHub Apps… have the prefix `ghu_`. **You can use the following endpoints for both types of OAuth tokens.**
  - 选 `grant` 而非 `token`：登出语义是"不再授权"，撤销 grant 会**连同该用户在该 App 下的全部令牌一并清掉**，不留悬空刷新令牌。
  - 🔧 **本条修正了一个旧结论**：此前因"客户端不持 secret"判定**无法程序化撤销**、只能引导用户去网页手动撤销；决策 #30 后该限制**消失**。这也让原型 / PRD 早已写下的"GitHub 侧的授权记录会一并撤销"从**"文案承诺、实现做不到"**变成**真的能兑现**（该矛盾随之消解）。
- **失败不阻塞登出**【已定】：离线 / 422 / 网络错误时**仍然清空本地凭据**，仅把提示降级为 `已退出登录 · 本机令牌已清除（未能撤销 GitHub 侧授权）`，并在设置页保留手动撤销跳转（`github.com/settings/apps/authorizations`）。
- ⚠️ **撤销授权 ≠ 卸载 App**：installation 仍然存在，重新登录只走授权流程、**不需要重新安装**（`GITHUB-APP-SETUP.md` §4.1）。
- **退出登录需二次确认**【已定】：确认弹层 + 影响说明（将清除本机凭据与缓存）。

### 3.7 App 标识与配置【已定】

| 项 | 取值 | 说明 |
|---|---|---|
| App 名 | `GitDuo` | GitHub App 注册名 |
| 回调 URL scheme | **`gitduo://oauth/callback`** | 自定义 scheme，**注册后即对外契约**，改动需回 GitHub 重配；须在 target 的 URL Types 中登记。⚠️ 裸名 scheme **不符合 RFC 8252 §7.1 的反域名要求**，且自定义 scheme 不是安全边界——残余风险与收敛方向见 §3.9 |
| `client_id` | 注册时生成 | 写入 `Secrets.xcconfig`（**git-ignored**），不进仓库 |
| `client_secret` | **内嵌进 App**（构建期由 `Secrets.xcconfig` 注入，仍 **git-ignored**） | 官方 **Required** 且无法规避（GitHub 不区分客户端类型，§3.1）；定位为**软机密**——挡得住随手薅、**挡不住反编译** ⇒ **不入库、不进日志**；**PKCE + `state` 仍是主防线**。另用于登出时撤销授权（§3.6） |
| 权限清单 | Contents(RW) · Issues(RW) · Pull Requests(RW) · Metadata(R) · Starring(RW) · Followers(RW) | 见 §3.4；Contents 必须 RW，否则无法提交文件；后两项为账号级权限（Star 与关注），缺失会 403 |
| 安装仓库范围 | **引导用户选「All repositories」** | 见 §3.5.4；选部分仓库会让仓库列表 / 搜索 / Starred 一起缺数据 |
| 令牌过期 | 开启 | user token 8 小时 + refresh token 6 个月（§3.2） |
| 安装时请求授权 | **关闭（不勾）** | ⚠️ 勾选后 GitHub 会走它自己发起的跳转（**无 `state`、无 `code_challenge`**）并锁定第一个回调 URL ⇒ PKCE 与 CSRF 防护双双失效；本项目**安装与授权分两步**（§1.3 / `GITHUB-APP-SETUP.md` §0.2） |

### 3.8 登录与授权页 UI【已定】

**门禁模型**：根视图按凭据状态二分，**不存在"已登录但功能受限"的中间态**。

```
RootView
├── 未认证 → LoginFlowView    ← 全屏覆盖；TabView 完全不构建
└── 已认证 → MainTabView      ← TabView + 4 个 NavigationStack（§8.1）
```

- 【已定】由 `AppEnvironment.authState`（`@Observable`）驱动：`.unauthenticated` / `.authenticating` / `.authenticated`，切换用系统动画。
- ⚠️ **未认证时不得构建 `TabView`**：否则 Tab 栏会在登录页下方可见，且各 Tab 的 `.task` 会带着空令牌发请求。

**状态机**

| 状态 | 界面 | 迁移条件 |
|---|---|---|
| 未认证 | 登录页（§4.0.1） | 点「使用 GitHub 登录」→ 授权中 |
| 授权中 | 系统浏览器会话（GitHub 授权页）+ 应用内等待态 | 回调成功 → 已认证；取消 / 失败 → 未认证 |
| 已认证 | 主界面（首页 Tab） | 401 且刷新失败 / 退出登录 → 未认证 |

**登录页 `LoginView`**

- 结构按 PRD §4.0.1：品牌区 → 权限预告卡（6 条）→「使用 GitHub 登录」→ 安全说明。
- 【已定】**权限清单单一数据源**：登录页的「预告」与授权页的「清单」由同一处 `[AppPermission]` 渲染（见 §3.4），**禁止两处各写一份文案**——预告与实际申请不一致，是授权类产品最伤信任的错误。
- 【已定】**登录页须承载「安装范围」引导**：安全说明中固定一行「安装页请选 All repositories（全部仓库）」，依据见 §3.5.4。这是用户点「登录」前唯一的提示位——GitHub 安装页本身不会解释漏选仓库的后果。
- 点击后按钮**立即禁用 + 内联 loading**，防连点重复开启授权会话。

**授权页**

- ⚠️ **授权页不是自绘页面**，而是 `ASWebAuthenticationSession` 里的 GitHub 官方页面，应用**无权也不应干预其外观**；原型中的「浏览器卡片 + 权限清单 + Authorize」是对该会话形态的还原。
- 应用侧真正要实现的只有三件事：
  1. 以 §3.1 步骤 3 的 URL 开启会话（`prefersEphemeralWebBrowserSession = false`，以复用系统已有的 GitHub 登录态）；
  2. 等待回调 / 取消 / 超时；
  3. 回调后转入等待态，串行执行 §3.1 步骤 5–8（校验 `state` → 换令牌 → 校验 → 写 Keychain）。
- 【已定】**不做应用内 `WKWebView` 授权**：需自管 Cookie 与登录态，既不可靠也有钓鱼风险（§14）。
- 等待态文案固定为「正在完成授权…」+ 回调 → 换令牌 → 写入本机的三步说明，**不暴露令牌内容**。

**取消与失败出口**

| 情况 | 出口 |
|---|---|
| 用户取消（会话被 dismiss） | 回登录页，**不写任何凭据**，不报错（属正常操作） |
| 回调 `state` 不匹配 | 回登录页 + 提示校验失败；丢弃该次 `code` |
| 换取令牌失败（网络 / 4xx） | 回登录页 + 可重试提示；**不缓存半成品凭据** |
| `GET /user` 校验失败 | 同上 |
| 会话超时 | 回登录页 + 提示重试 |

**退出登录（PRD §5.12）**

- 二次确认 → 清 Keychain 凭据 → 清账号绑定本地数据（最近访问 / 收藏夹与归属映射 / 搜索历史 / 按仓库的分支记忆 / 接口与图片缓存）→ 重置全部 `NavigationStack` 路径与 Tab 选中项 → `authState = .unauthenticated`。
- ⚠️ **不删除与账号无关的 UI 偏好**。
- 登出会**程序化撤销 GitHub 侧授权**（§3.6），弹层文案如实说明；**撤销失败时降级文案不得谎称已撤销**。

### 3.9 授权回调与 URL scheme 安全【已定】

**结论先行**：自定义 URL scheme（`gitduo://`）**不是安全边界**——iOS 不保证 scheme 唯一，任何 App 都能声明同一个 scheme，且 scheme 一旦发布即成为对外契约。因此本节的防御**不建立在"只有 GitDuo 能收到回调"这一假设上**，而是让回调内容**在没有本机私密信息时无法被利用**。

**风险场景（登记在案）**

| # | 场景 | 触发条件 | 后果 | 现有缓解 |
|---|---|---|---|---|
| A | **同 scheme 抢注**（被动劫持） | 恶意 App 声明 `gitduo://` 并静候真实回调 | 授权码被第三方收到 | ✅ **PKCE 兜住**：兑换令牌必须携带 `code_verifier`，它只存本机内存、**从不随回调传输**，故第三方拿到 `code` 也换不到令牌 |
| B | **伪造回调注入** | 恶意 App 直接向本 App 投递 `gitduo://oauth/callback?code=…` | 诱导 App 用攻击者的 `code` 兑换，或造成状态错乱 | ✅ `state` **一次性随机校验**，不匹配即丢弃；`code` 仅在期待回调的时间窗内被处理（§3.8 出口表） |
| C | **攻击者自建授权会话**（PKCE 的边界）⚠️ | 恶意 App 自行发起 OAuth（**自带它自己的** `code_verifier`），借受害者**已存在的 GitHub 登录态**让 GitHub 把 `code` 出到 `gitduo://oauth/callback` | 攻击者拿到 `code`，并用**它自己的** verifier 兑换成功 | ❌ **客户端侧无解**——PKCE 无法防御"发起方即攻击者"。唯一根治手段是 claimed HTTPS（Universal Link） |
| D | **scheme 冲突导致功能不可用** | 另一个 App 声明同一 scheme | 回调投递对象不确定，本 App 可能收不到回调 | ⚠️ 用户可感知（授权卡住），**不是静默风险**；换 scheme 需回 GitHub 重配 |

**已采纳的缓解（本期）**

1. **PKCE 强制**（§3.1 步骤 1 / 6）：`code_verifier` 仅存内存，不落盘、不进日志、不回显。
2. **`state` 一次性校验**：随机生成、仅用一次、不匹配即丢弃并回登录页。
3. **回调只承载 `code` 与 `state`，绝不承载令牌**；令牌交换由 App **直连 `github.com`** 完成（HTTPS + 系统证书校验），不经任何中间方。
4. **拒绝一切静默授权**：不使用 `prompt=none`、不依赖"已授权自动跳过"这类无交互出码路径——用户必然在系统浏览器里看到 GitHub 授权页并明确同意。这是场景 C 的**唯一软件侧抑制**。
5. **不用内嵌 `WKWebView`**（§14）：宿主进程能读取登录表单的全部输入，属禁项。
6. **scheme 只服务 OAuth 回调**：本期不做 `gitduo://repo/...` 深链（§8.2），也不承载密码重置 / 邀请 / magic-link 这类"把 deeplink 当凭证"的流程，攻击面收敛到单一入口。
7. **用 `ASWebAuthenticationSession` 的 `callbackURLScheme:`**，由系统把回调交给发起会话的实例，而非走 `UIApplication.openURL` 全局分发——降低（但不消除）被其他 App 截获的机会。

**遗留风险与收敛方向**

- ⚠️ **RFC 8252 §7.1 要求自定义 scheme 采用反域名形式**（如 `com.example.app:/oauth2redirect`），并明确指出多个 App 可注册同一 scheme；**现用的 `gitduo://` 属裸名 scheme，不符合该要求**（§3.7 已标注）。改成反域名形式成本很低（GitHub App 回调配置 + target URL Types + 文案），但同样**不能**解决场景 C。
- **收敛方向是 claimed HTTPS（Universal Link）**：`https://<domain>/oauth/callback` 由 `apple-app-site-association` 绑定本 App 的 Team ID，**OS 在路由前校验归属**，可同时根除场景 A 与 C；代价是需要一个可控域名并能静态托管 AASA（无后端亦可）。本期不具备条件，**登记为已知残余风险**；GitHub App 支持配置多个回调 URL，未来可保留 scheme 作为兜底。
- 与 Revert / 置顶同属"平台约束下的降级"，处置口径一致：**能做的做到位，做不到的写在明处**。

---

## 4. 网络层设计

### 4.1 客户端结构

| 客户端 | 职责 |
|---|---|
| `GitHubRESTClient` | 承载 90% 的能力：列表、详情、搜索、diff 原文、全部写操作 |
| `GitHubGraphQLClient` | 仅用于**多路聚合与 ProfileOwner 查询**（PR 详情、Issue 详情、贡献热力图、首页置顶仓库） |

两者共用一个 `HTTPTransport`（`URLSession` 封装），统一处理：请求头注入、令牌注入与刷新、ETag 条件请求、限流识别、错误归一化、重试。

### 4.2 统一请求头

```
Accept: application/vnd.github+json
Authorization: Bearer <access_token>
X-GitHub-Api-Version: 2026-03-10
User-Agent: GitDuo/2.0 (iOS)
```

- ⚠️ 【已定】API 版本头必须用 **`2026-03-10`**（旧值 `2022-11-28` 已过期）。
- PR diff / 提交 diff 需要原文时，把 `Accept` 换成 `application/vnd.github.diff`（或 `.patch`）。

### 4.3 错误模型

```swift
enum GitHubError: Error {
    case unauthorized              // 401 → 触发刷新/重新授权
    case forbidden(String)         // 403 → 可能是配额或权限
    case notFound                  // 404 → 资源不存在或无权访问（GitHub 会混同）
    case conflict                  // 409 → 提交冲突（SHA 已过期）
    case validation([String])      // 422 → 参数错误
    case rateLimited(resetAt: Date, isSecondary: Bool)  // 配额耗尽
    case graphQLErrors([String])   // GraphQL：HTTP 200 + body.errors
    case transport(URLError)       // 网络层
    case decoding(Error)
}
```

**两条容易踩的坑**：
1. **404 不等于不存在**——私有仓库无权限时 GitHub 也返回 404。UI 文案要写成"仓库不存在或你没有访问权限"，不能断言"不存在"。
2. **GraphQL 的错误在 body 里**——返回 `200 OK` 且 `body.errors` 有值，甚至可能 `data` 与 `errors` 同时存在（部分成功）。**绝不能只看 HTTP 状态码判定成功**。

### 4.4 分页

- 【已定】REST 统一用 `Link` 响应头解析 `next`，封装为 `Page<T>`（`items` + `nextCursor`）。
- 列表默认 `per_page=30`；搜索类接口 `per_page=30`（上限 100）。
- **【已定】分页交互采用混合策略**：
  - **普通列表**（仓库 / Issue / PR / Commits / Star / 分支等）→ **滚动到底自动加载**下一页；底部显示行内加载指示，失败给「重试」行，**不遮挡已有内容**。
  - **搜索结果** → **「加载更多」按钮**手动触发。⚠️ 依据：Search 独立配额仅 **30 次/分钟**（代码搜索 ≈10），且结果**上限 1000 条**——自动翻页极易瞬间触顶，手动触发把配额交还用户控制。
- 每个列表 ViewModel 暴露 `state: { items, isLoading, canLoadMore, error }`；下拉刷新重置到第一页。
- ⚠️ 两个硬上限：**搜索结果最多 1000 条**（10 页 × 100）；**搜索代码端点只搜默认分支、且文件 < 384KB**。

### 4.5 限流与配额

| 桶 | 额度 | 说明 |
|---|---|---|
| REST `core` | 5000 请求/小时 | 每请求 1 单位，高度可预测 |
| GraphQL `graphql` | 5,000 点/小时（**按用户计**：GitHub App 代表用户行事时与个人令牌共用同一额度，见 §3.1） | 按查询**潜在最大节点数**预扣，非实际返回数；计点公式与四个场景的预算见 §13.2 |
| Search（仓库/用户/Issue） | **30 请求/分钟** | 独立于 core 桶 |
| Search code | **≈10 请求/分钟** | 全 API 最紧的限额（官方文档存在 9/10 两种表述，**按 9 保守预算**） |

**处置策略**【已定】：
1. **条件请求优先**：列表与详情一律先带 ETag 发条件请求，304 不耗配额。
2. **限流器分级**：搜索类请求走独立的 `RateLimiter`（令牌桶），代码搜索**串行 + 手动间隔**，绝不像普通请求那样并发。
3. **`X-Poll-Interval`**：轮询类请求必须遵守服务端给的轮询间隔下限。（本期无轮询类请求——通知本期不做，见 §3.5.3；此条作为通用纪律保留。）
4. **配额可见**：`GET /rate_limit` 可在设置页暴露"剩余配额"，异常时给出提示（可选）。
5. **GraphQL 查询设计纪律**：`first` 尽量小、避免嵌套大连接（预扣按最坏情况计费，容易"莫名烧光"）。

### 4.6 API 端点映射总表（逐功能）

> 这张表是本文档与 PRD 的对齐核心：**PRD 中的每个功能点，在此都能找到技术落点**。

#### 4.6.1 首页 / 搜索

| 功能（PRD） | 数据来源 | 端点 / 字段 | 写操作 | 缓存 |
|---|---|---|---|---|
| 首页置顶仓库 | **GraphQL** | `viewer.pinnedItems(first:6, types:REPOSITORY)`，一次拿回全部置顶及其仓库元数据 | **无**（官方无置顶 mutation，见 §9.1） | 内存 + 磁盘，可长缓存 |
| 首页最近访问 | **本地** | UserDefaults（全名 + 相对时间），最多 6 条 | 本地 | — |
| 搜索 · 仓库 | REST Search | `GET /search/repositories?q=` | — | 30/min 限流，短时内存缓存 |
| 搜索 · 用户 | REST Search | `GET /search/users?q=`；点开展示 `GET /users/{username}` | — | 同上 |
| 搜索 · 代码 | REST Search | `GET /search/code?q=`（需 ≥1 个非限定词；仅默认分支） | — | **10/min，串行** |
| 搜索 · Issue·PR | REST Search | `GET /search/issues?q=`（PR 亦由此端点返回） | — | 30/min |
| 搜索历史 | **本地** | UserDefaults，最多 8 条 | 本地 | — |
| 热门关键词 | **本地/静态** | 内置词表（可后续改为远程配置） | — | — |

#### 4.6.2 仓库列表 / 仓库详情（自己的仓库）

| 功能 | 端点 | 备注 |
|---|---|---|
| 仓库列表（全部/公开/私有/Starred） | `GET /user/repos?affiliation=owner&sort=updated`；Starred 用 `GET /user/starred` | 公开/私有按 `private` 字段本地过滤 |
| 仓库头部 + Star/Watch/Fork 数 | `GET /repos/{owner}/{repo}` | |
| Star 切换 | `PUT` / `DELETE /user/starred/{owner}/{repo}` | 计数由响应后本地 +1/−1，无需重拉 |
| Watch | `GET /repos/{owner}/{repo}/subscription` | **本期只读计数，不实现订阅动作**（§3.5.2） |
| Fork | `POST /repos/{owner}/{repo}/forks` | |
| 分支列表 | `GET /repos/{owner}/{repo}/branches` | |
| 文件树 / 目录 | `GET /repos/{owner}/{repo}/contents/{path}?ref={branch}` | 目录清单 |
| 递归文件树 | `GET /repos/{owner}/{repo}/git/trees/{sha}?recursive=1` | 代码搜索/全局定位时用 |
| README | `GET /repos/{owner}/{repo}/readme`（`Accept: application/vnd.github.raw`） | 块级渲染见 §11.1 |
| Issue 列表（开放/已关闭） | `GET /repos/{owner}/{repo}/issues?state=open\|closed` | ⚠️ **会混入 PR，需按 `pull_request` 字段过滤** |
| 新建 Issue | `POST /repos/{owner}/{repo}/issues`（`title`,`body`,`labels[]`） | |
| Issue 详情 / 评论 | `GET /repos/{owner}/{repo}/issues/{n}`；`GET/POST …/issues/{n}/comments` | 也可用 GraphQL 聚合（§4.6.5） |
| 关闭 / 重开 Issue | `PATCH …/issues/{n}`，`state: closed\|open` | |
| 标签列表 | `GET /repos/{owner}/{repo}/labels` | |
| 新建标签 | `POST /repos/{owner}/{repo}/labels`（`name`,`color`，**不带 `#`**） | 10 色板 → 十六进制 |
| PR 列表（开放/已合并） | `GET /repos/{owner}/{repo}/pulls?state=open\|closed` | 已合并 = `state=closed` 且 `merged_at != null`，需本地区分 |
| PR 详情 | `GET /repos/{owner}/{repo}/pulls/{n}` | |
| PR 文件清单 | `GET …/pulls/{n}/files` | 含 `patch` 字段（单文件 diff） |
| PR diff 原文 | `GET …/pulls/{n}`，`Accept: application/vnd.github.diff` | **REST 独有**，GraphQL 无等价 |
| PR 对话评论 | `GET/POST …/issues/{n}/comments` | PR 的会话评论走 issue 端点 |
| PR 评审评论 | `GET …/pulls/{n}/comments` | 行内评论（本期只读展示） |
| PR Commits | `GET …/pulls/{n}/commits` | |
| 合并 PR | `PUT …/pulls/{n}/merge`，`merge_method: merge\|squash\|rebase` | 三种方式一一对应 |
| 关闭 PR | `PATCH …/pulls/{n}`，`state: closed` | |
| 提交列表 | `GET /repos/{owner}/{repo}/commits?sha={branch}` | 分支联动 |
| 提交详情 + 文件 diff | `GET /repos/{owner}/{repo}/commits/{sha}` | 响应含 `files[].patch` |
| 提交 diff 原文 | `Accept: application/vnd.github.diff` | |
| **Revert 提交** | ⚠️ **REST 无原生 revert 端点** → **本期不在客户端实现**，入口跳转网页端（§9.7.3） | 【已定】 |
| 新建 / 编辑 / 上传文件 | `PUT /repos/{owner}/{repo}/contents/{path}`（`message`,`content`(base64),`sha`(更新时必需),`branch`） | ≤1MB |
| 大文件 / 多文件提交 | ❌ **本期不引入 Git Data API**（`POST /git/blobs` → `trees` → `commits` → `PATCH /git/refs/…`） | 与 §9.6 的能力边界一致 |
| 上传图片 | 同文件上传（二进制 → base64） | 相册取图需降采样 |
| 创建分支 | `POST /repos/{owner}/{repo}/git/refs`（`refs/heads/x`, `sha`） | |
| 删除分支 | `DELETE /repos/{owner}/{repo}/git/refs/heads/{branch}` | 删前校验未合并提交 |
| 合并分支 | `POST /repos/{owner}/{repo}/merges`（`base`,`head`） | 冲突 → 引导网页端 |
| 创建 PR（提交面板"新分支 + PR"） | `POST /repos/{owner}/{repo}/pulls` | |

#### 4.6.3 探索（他人仓库）

| 功能 | 端点 | 备注 |
|---|---|---|
| 趋势榜（新星 / 活跃） | `GET /search/repositories`（`created:` / `pushed:` 限定符） | 两榜各一次请求，按需加载；见 §9.10.1 |
| 他人仓库详情 | `GET /repos/{owner}/{repo}` | |
| 语言构成 | `GET /repos/{owner}/{repo}/languages` | **REST 独有**（GraphQL 无等价） |
| Latest Release | `GET /repos/{owner}/{repo}/releases/latest` | |
| 贡献者 | `GET /repos/{owner}/{repo}/contributors` | |
| 文件树 / 分支切换（只读） | 同 §4.6.2 | 只读态由客户端控制，不额外请求 |
| 探索 Issues / PR 列表 | `GET …/issues`、`GET …/pulls` | 只读模式 |

#### 4.6.4 我的 / 设置

| 功能 | 端点 | 备注 |
|---|---|---|
| 个人资料 | `GET /user` | |
| 仓库 / Star / Follower 统计 | `GET /user`（`public_repos`,`followers`）+ Starred 总数 | |
| **贡献热力图** | **GraphQL** `viewer.contributionsCollection.contributionCalendar` | ⚠️ **REST 无等价端点**，必须走 GraphQL |
| 我的 Star | `GET /user/starred` | |
| 取消 Star | `DELETE /user/starred/{owner}/{repo}` | |
| 我的 PR / Issue | `GET /search/issues?q=author:@me type:pr\|issue` | |
| 关注用户 | `PUT /user/following/{username}` | |
| 查看用户公开仓库 | `GET /users/{username}/repos` | |
| 主题 / 清除缓存 / 版本 | 本地 | |

#### 4.6.5 使用 GraphQL 的四个场景（其余全部 REST）

| 场景 | 理由 | 大致查询 |
|---|---|---|
| **PR 详情聚合** | 单屏需 PR 基础信息 + 评论 + 评审 + commits + 文件统计，REST 需 4–5 次往返 | `repository.pullRequest(number:) { … comments(first:) reviews(first:) commits(first:) files(first:) }` |
| **Issue 详情聚合** | 同上（基础信息 + 评论 + 时间线） | `repository.issue(number:) { … comments(first:) }` |
| **贡献热力图** | REST 无等价端点 | `viewer.contributionsCollection { contributionCalendar { weeks { contributionDays { … } } } }` |
| **首页置顶仓库** | ⚠️ **REST 完全没有置顶端点**，只有 GraphQL 提供 | `viewer.pinnedItems(first: 6, types: REPOSITORY) { nodes { … on Repository { nameWithOwner } } }`（配合 `pinnedItemsRemaining` / `viewerCanChangePinnedItems` 判状态） |

**纪律**：GraphQL 只做聚合，**写操作一律走 REST**（REST 用 URL 直接标识对象；GraphQL 多数要先查 node ID，且错误语义更复杂）。

---

## 5. 缓存与配额策略

### 5.1 三层缓存

| 层 | 内容 | 生命周期 | 实现 |
|---|---|---|---|
| L1 内存 LRU | 已解码的领域模型（列表首页、当前仓库树、当前 PR/Issue） | 随进程 | `actor CacheStore`，容量按条数/字节双限 |
| L2 HTTP 缓存 | 原始响应体 + `ETag` / `Cache-Control` | 按 `Cache-Control` | **自建**（`actor`，内存 + 上限 50–100MB）。⚠️ **不用系统 `URLCache`** —— 它会把**序列化请求对象**一并落盘，`Authorization` 头因此进磁盘（2026-10-06 实测，决策 #32） |
| L3 磁盘持久化 | JSON 快照 + ETag + 时间戳（离线可看） | 7–30 天，按 LRU 淘汰 | 自建目录 `Caches/GitDuoCache/`，key = 规范化 URL 的 SHA256 |

**为什么自建 L3 而不直接用 SwiftData**：缓存是"可丢弃的加速器"，不需要迁移、关系与查询能力；文件 + LRU 更简单、可控、易清理（PRD §4.19 的"清除缓存"要能报告大小并一键清空）。

### 5.2 ETag 条件请求

【已定】除写操作外，所有 GET 默认走条件请求：

1. 查 L3/L1 得到 `etag` → 请求带 `If-None-Match`。
2. 收到 **304** ⇒ 直接用本地副本，**不消耗配额**，刷新 `fetchedAt`。
3. 收到 200 ⇒ 更新缓存与 ETag。
4. 写操作成功后**主动失效**相关 key（例：提交文件后失效该仓库的 contents / commits / branches）。

⚠️ 注意：ETag 是**按 URL 维度的**，同一数据用不同参数（`?ref=`、`?state=`、`per_page=`）请求会拿到不同 ETag，缓存 key 必须包含完整查询串。

### 5.3 图片与降采样

- 头像与截图走 `AsyncImage`（iOS 27 已内置缓存）。
- 【已定】头像按展示尺寸降采样后再入缓存（避免为 32pt 圆头像缓存 460px 原图）；GitHub 头像 URL 支持 `?s=<size>` 参数，直接请求所需尺寸。
- 列表滚动中禁止同步解码大图。

### 5.4 缓存失效与清理

| 触发 | 动作 |
|---|---|
| 任意写操作成功 | 失效该仓库下的相关路径 |
| 下拉刷新 | 强制跳过 ETag，直接 200 |
| 令牌变更 / 登出 | 清空全部缓存（含 L3） |
| 设置页"清除缓存" | 清 L2 + L3，报告释放大小 |
| 磁盘压力 / 超过 TTL | LRU 淘汰 |

---

## 6. 领域模型与数据流

### 6.1 三层模型

```
DTO（GitHubAPI，与 JSON 一一对应，可空字段多）
   │  Mapper（纯函数，可单测）
   ▼
Domain Model（领域层，字段洁净、语义明确、不含可空噪音）
   │  ViewModel 组装
   ▼
View State（表现层，为 UI 量身裁剪，含 loading/empty/error）
```

**为什么一定要分三层**：GitHub 的 DTO 有大量历史包袱（`closed_at` 与 `state_reason` 并存、PR 与 Issue 共用结构、`pull_request` 字段判定类型等）。若直接把 DTO 喂给 View，业务判断会散落到各处。Mapper 是唯一允许处理"平台怪癖"的地方。

### 6.2 核心领域模型（拟定字段）

| 模型 | 关键字段 |
|---|---|
| `Repository` | `owner`,`name`,`fullName`,`description`,`isPrivate`,`primaryLanguage`,`starCount`,`forkCount`,`defaultBranch`,`pushedAt`,`license`,`topics`,`permissions`（REST 返回的 `{admin,maintain,push,triage,pull}` 全集；**`push == true` 即可写性判定依据**，见 §8.1 / §9.11 / 附录 B） |
| `TreeEntry` | `name`,`path`,`kind(.file/.dir)`,`lastCommitMessage` |
| `FileContent` | `path`,`text`,`sha`,`size`,`isBinary` |
| `Issue` | `number`,`title`,`state(.open/.closed)`,`labels`,`author`,`createdAt`,`commentCount`,`body` |
| `PullRequest` | `number`,`title`,`state(.open/.merged/.closed)`,`head`,`base`,`author`,`updatedAt`,`additions`,`deletions`,`changedFileCount`,`mergeable` |
| `PullRequestState` | 三态枚举：开放 / 已合并 / 已关闭（**由 `state` + `mergedAt` 共同判定**） |
| `Comment` | `id`,`author`,`createdAt`,`body`,`isReview`,`reviewState(.approved/.changesRequested/.commented)` |
| `Commit` | `sha`,`message`,`author`,`committedAt`,`additions`,`deletions`,`files` |
| `DiffHunk` / `DiffLine` | `header`；`kind(.context/.add/.delete)`,`oldLine`,`newLine`,`text` |
| `Label` | `name`,`hexColor` |
| `Folder` | `name`,`isDefault`（收藏夹，**本地实体**；`isDefault` 的内置收藏夹不可重命名 / 删除；**`count` 为派生值**，由 `favMap` 推导，见 §9.12） |
| `Notification` | `id`,`subjectType`,`reason`,`title`,`repository`,`isUnread`,`updatedAt` |
| `UserProfile` | `login`,`name`,`avatarURL`,`bio`,`repoCount`,`followerCount` |
| `ContributionCalendar` | `total`；`weeks: [[day(level, date)]]` |
| `TrendingRepo` | `Repository` + `weeklyStarDelta`,`contributors` |

### 6.3 数据流原则

- 单向：View 只读 ViewModel 的不可变状态；用户动作调用 ViewModel 的方法；ViewModel 调 Repository；Repository 调 Service/Client。
- ViewModel 为 `@Observable` + `@MainActor`；网络与缓存操作在 actor 内执行后回到主 actor 更新状态。
- **页面级状态**（当前分区、当前路径）**归 ViewModel**，不塞进全局单例——否则多入口进入同一页面时会互相污染状态。
- **仓库级会话状态**（当前分支）归 **`RepositoryScope`**，按仓库全名分别记忆：同一仓库内「代码」与「Commits」共用，**仓库之间互不影响**。它既不是"页面级"（离开页面仍保留），也不是"全局唯一值"（全局单值会串分支）。解析规则见 §9.4。

---

## 7. 本地持久化

### 7.1 存储选型

| 数据 | 存储 | 理由 |
|---|---|---|
| `access_token` / `refresh_token` | **Keychain** | 唯一安全位置 |
| 账号登录名、令牌过期时间 | Keychain 附属 / UserDefaults | 非敏感元数据 |
| 最近访问（全名 + 时间戳，≤6） | UserDefaults（JSON） | 同上 |
| 收藏夹（`name` / `isDefault`）与归属映射 `favMap` | UserDefaults（JSON）或轻量文件夹 | 数据量小，无查询需求；**`count` 不落盘**，由映射推导（§9.12） |
| 搜索历史（≤8） | UserDefaults | 同上 |
| 当前分支（**按仓库**，`branchByRepo`） | 内存 + 可选 UserDefaults | 恢复现场；作用域见 §9.4.1 |
| 分区 / 滚动位置等页面态 | 内存 | 页面销毁即丢，无需持久化 |
| 网络响应缓存 | 文件目录 + LRU（§5.1） | 大对象、可丢弃 |

**不引入数据库**：本期所有本地数据都是"小规模、无关系、无复杂查询"的形态，UserDefaults + JSON 足够；引入 SwiftData/CoreData 会增加迁移与并发复杂度而无收益。

### 7.2 关键本地逻辑

- **最近访问**：进入任意仓库详情（自己的或他人的）后写入，去重后置顶，裁剪到 6 条。⚠️ 写入动作**不得直接触发首页重绘**（会造成写入→重绘→再写入的循环），应由仓储层落盘、首页在下次出现时读取。
- **置顶仓库**：**不是本地数据**——只读同步自 GitHub 个人主页（GraphQL `viewer.pinnedItems`），本地仅缓存查询结果；登出时随缓存一并清理。
- **收藏语义**：收藏是**纯本地**能力（私人收藏夹，不影响 Star 数）。两段式交互由 ViewModel 维护 `state: { isFavorited, currentFolder }` 驱动；`isFavorited` / `currentFolder` 一律**查 `favMap` 得出**，不另存一份布尔量（两份状态必然不同步）。计数推导规则见 §9.12。
- **当前分支**：`RepositoryScope` 内以 `branchByRepo: [String: String]` 按仓库全名分别记忆；对外只暴露 `branch(for:)`（含回落）与 `select(branch:for:)`。⚠️ **不得**写成单个 `currentBranch` 全局变量——那会使仓库之间串分支（§9.4.1）。
- **多账号预留**：所有本地数据以 `login` 作为命名空间前缀，为未来多账号切换留出结构（本期不做）。

---

## 8. 导航与状态架构

### 8.1 结构

```
RootView                             ← 按 authState 二分（§3.8）
├── .unauthenticated / .authenticating → LoginFlowView （登录页 / 授权等待态 · 全屏）
└── .authenticated → MainTabView
    └── TabView(selection:)          ← 系统组件，Liquid Glass 自动生效
        ├── Tab 首页   → NavigationStack(path:) ← 独立栈
        ├── Tab 仓库   → NavigationStack(path:)
        ├── Tab 探索   → NavigationStack(path:)
        └── Tab 我的   → NavigationStack(path:)
```

- 【已定】**未认证时不构建 `TabView`**：登录流程是**门禁**而非普通页面，不占任何 Tab 的导航栈（§3.8）。
- 【已定】**每个 Tab 各持一条独立导航栈**，切 Tab 保留各自层级（PRD §2.1）。
- 【已定】路由用值类型枚举 `Route`（`Hashable`），配 `navigationDestination(for: Route.self)`；**不使用** `NavigationLink(destination:)` 的闭包式写法（难以单测、难以程序化导航）。
- **可写性判定唯一来源**：`Repository.permissions.push == true`（`permissions` 字段定义见 §6.2）。真实产品中"自己的仓库"= 用户拥有写权限的任意仓库，**不按名称前缀或任何静态名单判定**，也不存在"主仓库"概念。

### 8.2 路由与深链

`Route` 枚举覆盖 PRD 的全部推入页（页面清单见 PRD §4；其中通知页本期不做，见 §3.5.3）。
其关联值引用两个辅助类型 `RepoSection` 与 `EditorMode`，定义如下
（**2026-10-05 补齐**：此前两者只在 `Route` 里被引用，本文档从未给出取值）：

```swift
/// 仓库详情的四个分区（依据 PRD §4.4：代码 / Issues / Pull Requests / Commits）
enum RepoSection: String, Hashable, Sendable, CaseIterable {
    case code
    case issues
    case pullRequests
    case commits
}

/// 编辑器的打开模式（依据 PRD §4.6）
enum EditorMode: Hashable, Sendable {
    /// 新建文件（需输入路径）
    case create
    /// 编辑既有文件
    case edit
}

enum Route: Hashable {
    case search
    case repoDetail(fullName: String, section: RepoSection, path: String?)
    case exploreRepoDetail(fullName: String, path: String?)
    case fileView(fullName: String, path: String, readOnly: Bool)
    case editor(fullName: String, path: String?, mode: EditorMode)
    case commitDetail(fullName: String, sha: String, readOnly: Bool)
    case branches(fullName: String)
    case issueDetail(fullName: String, number: Int)
    case newIssue(fullName: String)
    case prDetail(fullName: String, number: Int, readOnly: Bool)
    case exploreIssueList(fullName: String)
    case explorePRList(fullName: String)
    case stars
    case folders
    case settings
}
```

- **只读态通过参数显式传递**（`readOnly: Bool`），而不是让下层页面自行推断当前仓库归属——推断会造成权限判定散落、口径不一。
- 深链（`gitduo://repo/owner/name`）本期不做，但路由为值类型天然支持，后续接 `onOpenURL` 即可。
- ⚠️ **本期 scheme 只服务 OAuth 回调**（§3.9）：不注册任何深链路由，`onOpenURL` 仅保留授权回调分支——scheme 的攻击面因此收敛为单一入口。

### 8.3 页面与路由对照

| PRD 页面 | 路由 / 容器 |
|---|---|
| 登录页 / 授权等待态 | `LoginFlowView` —— **全屏门禁，不是路由**；由 `authState` 驱动（§3.8） |
| 首页 / 仓库 / 探索 / 我的 | Tab 根页（Tab 页形态，大标题 + 可滚动）。**共 4 个**，通知 Tab 本期不做（§3.5.3） |
| 搜索 | `.search` |
| 仓库详情（自己的） | `.repoDetail` |
| 探索仓库详情（他人只读） | `.exploreRepoDetail` |
| 文件查看 | `.fileView(readOnly:)` |
| 编辑器 | `.editor(mode:)` |
| 提交详情 | `.commitDetail(readOnly:)` |
| 分支管理 | `.branches` |
| Issue 详情 / 新建 Issue | `.issueDetail` / `.newIssue` |
| PR 详情 | `.prDetail(readOnly:)` |
| 探索 Issues / PR 列表 | `.exploreIssueList` / `.explorePRList` |
| 我的 Star | `.stars` |
| 我的收藏 | `.folders` |
| 设置 | `.settings` |

### 8.4 弹层与轻提示

- **弹层**：用系统 `.sheet` + `.presentationDetents([.medium, .large])`。PRD 的 14 类弹层各自实现为一个 `View`，由调用方以 `.sheet(item:)` 呈现（用 `Identifiable` 的 `SheetRoute` 枚举驱动，避免多个 `isPresented` 布尔量互相打架）。
- **轻提示**：自定义 Toast 组件（深色胶囊、2.4 秒自动消失），以 `.overlay(alignment: .bottom)` 挂在根容器上，不阻塞交互。

**14 类弹层的技术落地**：

| 弹层（PRD §5） | 数据来源 | 关键实现点 |
|---|---|---|
| 5.1 清除最近访问确认 | 纯本地 | 破坏性操作 → 红底按钮 + 二次确认 |
| 5.2 标签选择 / 新建 | `GET/POST …/labels` | 名称去重本地先行；色值去除 `#` |
| 5.3 合并 Pull Request | `PUT …/pulls/{n}/merge` | 三选项 → `merge`/`squash`/`rebase` |
| 5.4 探索筛选 | 本地状态 + Search 限定符 | 再点当前项 = 取消；空选 = 全部 |
| 5.5 选择收藏列表 | 纯本地 | 两段式；点当前列表 = 移出收藏 |
| 5.6 新建收藏夹 | 纯本地 | 重名 → 提示并自动选中 |
| 5.7 切换分支 | `GET …/branches` | 按 `readOnly` 决定是否显示"管理分支"入口 |
| 5.8 添加文件 | — | 三个出口分别进编辑器 / 提交流程 |
| 5.9 提交更改 | Contents API（单文件 ≤1MB） | 目标分段（当前分支 / 新分支+PR）+ 409 冲突出口；大文件引导网页端 |
| 5.10 用户资料 | `GET /users/{username}` | 关注 / 查看公开仓库（均需真实调用，非占位） |
| 5.11 退出登录确认 | 纯本地 | 清 Keychain + 清账号绑定数据 + 重置导航栈（§3.8） |
| 5.12 收藏夹操作菜单 | 纯本地 | 标题带名称与项目数；两个动作行（重命名 / 删除收藏夹） |
| 5.13 重命名收藏夹 | 纯本地 | 输入框预填原名；空名与重名拦截；与原名相同则直接关闭 |
| 5.14 删除收藏夹确认 | 纯本地 | 红底 + 二次确认并回显项目数；`isDefault` 的收藏夹**不进入本弹层**，直接提示不可删除 |

### 8.5 加载态与骨架屏【已定】

**三档统一**，各页面不得自行发挥：

| 场景 | 表现 |
|---|---|
| **首屏加载**（进入页面、首次拉数据） | **骨架屏**：与真实内容同尺寸的占位块（列表行 / 卡片 / 文件树），带轻微呼吸动画。**尺寸必须匹配真实布局**，避免数据到达时跳动 |
| **分页 / 下拉刷新** | 行内加载指示（列表底部 spinner / 系统下拉刷新控件），**不遮挡已有内容**；分页失败在底部给「重试」行 |
| **操作类**（提交、合并、关闭 Issue、Star） | 按钮内联 loading + **禁用**，防重复提交；失败恢复可点并给 Toast |

- ⚠️ 骨架屏属**内容层**：一律**实色**，**不得加 Liquid Glass**（§10.2）。
- 骨架动画须响应系统「降低动态效果」设置（§10.5）。
- 空态与骨架屏是两回事：**加载中 ≠ 无数据**，不得用空态文案代替加载态。

---

## 9. 核心功能技术方案

### 9.1 首页

| 元素 | 方案 |
|---|---|
| 置顶仓库 2 列网格 | **GraphQL** `viewer.pinnedItems(first:6, types:REPOSITORY)` 一次取回全部置顶及其元数据（名称 / 描述 / 语言 / Star / Fork / 私有）→ 内存 + 磁盘缓存 |
| 「管理」链接 | ⚠️ **官方无置顶写接口** → 打开 `https://github.com/{login}` 并提示（与 Revert 同一处置模式，§9.7.3） |
| 最近访问 | 本地，进入详情页时写入（§7.2） |
| 清除确认弹层 | 纯本地操作 + 二次确认 |
| 搜索图标 | 导航到 `.search`（与仓库页、探索页共用同一页面） |

**空态**：个人主页无置顶时显示 `GitHub 个人主页还没有置顶仓库` + 引导去 `Customize your pins`。

**性能**：置顶**一次查询**即拿回全部元数据（≤6 个），无需逐个 `GET /repos/{owner}/{repo}`，也不占用 REST core 桶；结果可长缓存，仅下拉刷新时重新查询。

**依据（为何不能在本机增删置顶）**：`ProfileOwner` 接口只暴露 `pinnedItems` / `pinnableItems` / `pinnedItemsRemaining` / `viewerCanChangePinnedItems` 等**只读字段**，GraphQL 变更集内**不存在**任何置顶相关 mutation（社区 feature request 至今未实现）；REST 侧也完全没有置顶端点。因此"在 App 内增删置顶"不具备实现条件，只能跳网页端——与 Revert 属同一类平台限制（§9.7.3）。

### 9.2 搜索

| 项 | 方案 |
|---|---|
| 边输边搜 | **防抖 300ms** + **任务取消**（新输入到来即取消上一条请求），避免打满 30/min |
| 四范围 | 四个 Search 端点；**切换范围只重筛当前关键词**，不重置输入 |
| 结果上限 | 搜索结果最多 1000 条；超出不提示（与 GitHub 一致） |
| 代码范围 | ⚠️ 需 ≥1 个非限定词、只搜默认分支、文件 <384KB、**≈10 次/分钟** → 串行 + 本地防抖加长（建议 500ms） |
| Issue·PR 范围 | `GET /search/issues`，用 `type:pr` / 类型字段区分 PR 与 Issue |
| 回车 | 写入本地历史（≤8，去重）并提示 |
| 最近搜索 / 热门词 | 本地 |

**配额提示**：搜索是独立且**很紧**的配额（30/min，代码 10/min）。UI 上的"边输边搜"必须配合防抖与取消，否则用户连打几个字符就会触发 403。

### 9.3 仓库列表

- 数据：`GET /user/repos`（自己的）；Starred 段用 `GET /user/starred`。
- 分段过滤：`全部 / 公开 / 私有 / Starred`。前三段可在**本地**基于 `private` 字段过滤（一次拉取即可），Starred 需另一份数据源。
- 【已定】分段切换不重新请求（已全量拉取首页），但"加载更多"时按当前段决定后续请求。

### 9.4 仓库详情（自己的仓库 · 四分区）

- 头部：`GET /repos/{owner}/{repo}`。
- 分区切换**不重新请求头部**，只切换内容区；分区状态存 ViewModel。
- 代码分区：见 §9.5。Issues / PR：见 §9.8 / §9.9。Commits：`GET …/commits?sha={branch}`，**随当前分支联动**。
- **当前分支是按仓库分别记忆的会话状态**（同一仓库内代码与 Commits 共用，跨仓库互不影响）；切分支后失效该仓库的 contents/commits 缓存。

#### 9.4.1 分支解析规则【已定】

进入任一仓库时执行，**禁止**用单个全局 `currentBranch`（否则会出现"仓库 B 显示仓库 A 的分支，而 B 根本没有该分支"的未定义状态）：

| 情形 | 结果 |
|---|---|
| 该仓库记忆的分支仍在 `GET /repos/{owner}/{repo}/branches` 结果中 | 沿用记忆值 |
| 记忆的分支**已不存在**（被删除 / 改名 / 无权限） | **回落 `Repository.defaultBranch`**，并失效该仓库的 contents/commits 缓存 |
| 无记忆（首次访问该仓库） | 直接用 `Repository.defaultBranch` |
| 切到「他人仓库详情」（§9.11） | 同规则，但只用于浏览，记忆与自己的仓库各存一份 |

- 实现：`RepositoryScope.branch(for fullName: String) -> String` + `private var branchByRepo: [String: String]`；`Repository.defaultBranch` 作为回落值（§6.2 实体字段）。
- 分支列表本身来自 `GET …/branches`（已带缓存），因此"分支是否存在"的校验**不额外消耗请求**。
- 记忆为会话级（可持久化以提升体验）；**登出时清空**（§3.6），与其它账号绑定数据一致。

### 9.5 代码浏览与文件树

| 场景 | 端点 |
|---|---|
| 逐级目录 | `GET /repos/{owner}/{repo}/contents/{path}?ref={branch}` |
| 面包屑跳级 | 直接请求目标 path，或从已在内存的路径栈回退（避免重复请求） |
| 文件查看 | `GET …/contents/{path}`（小文件返回 base64；大文件用 `Accept: application/vnd.github.raw` 取原文） |
| README 渲染 | `GET …/readme`（raw）→ §11.1 块级渲染 |

- ⚠️ **二进制文件**（图片等）需识别并展示预览而非当文本渲染。
- ⚠️ Contents API 对 **>1MB 的文件**不返回内容（返回 `content: ""`），需回退到 `Accept: application/vnd.github.raw` 取原文（`git/blobs` 属 Git Data API，本期不引入）。**只读浏览大文件仍然支持**——不做的是"上传/编辑提交大文件"。
- 路径合法性：进入目录前校验 path 拼接，避免 `..` 与双重斜杠。

### 9.6 编辑器与提交

**能力边界**【已定】——本期**仅支持单文件提交，不引入 Git Data API**：

| 场景 | 通道 |
|---|---|
| 单文件、≤1MB、无并发冲突 | **Contents API**：`PUT /repos/{owner}/{repo}/contents/{path}`（携带 `sha` 表示更新） |
| >1MB 或二进制大文件 | **本期不支持** → UI 提示并引导到 GitHub 网页端 |
| 多文件一次提交（暂存队列） | **本期不做**（编辑器保持「保存即一次提交」） |

**为何不做**：暂存队列需在客户端维护跨页面的暂存状态（文件集合、各自内容、基线 sha、冲突检测），并以一次 commit 携带多个 tree 变更——收益集中在"批量改多个文件"这一**桌面端**场景，移动端以单文件改动为主。砍掉后**整套 Git Data API（blob→tree→commit→ref）链路都不必实现**，范围显著缩小；且它也是 Revert 客户端实现的前置依赖（§9.7.3），一并去掉后依赖链更干净。若后续要做，只需在 `CommitService` 内新增一条通道，不触及上层。

**提交面板的两条目标路径**：
- 「提交到当前分支」→ 直接在 `branch` 上提交。
- 「新分支 + PR」→ 先 `POST /git/refs` 建分支 → 在新分支提交 → `POST /pulls` 建 PR。

**409 冲突保护**：更新文件时若远端已变更，GitHub 返回 409。UI 给出两个出口：**查看最新版**（拉取新 sha 与内容，让用户合并后重提）/ **强制覆盖**（用最新 sha 重发）。⚠️ 强制覆盖属危险操作，需二次确认。

### 9.7 分支、合并与 Revert

#### 9.7.1 分支管理
- 列表：`GET /repos/{owner}/{repo}/branches`——**本页只列当前仓库的分支**，标题带仓库全名。
- 新建：`POST /git/refs`（`ref: refs/heads/{name}`, `sha:` 当前分支 HEAD）。
- 删除：`DELETE /git/refs/heads/{branch}`。**默认分支不可删**（UI 不给入口 + 逻辑层拦截，同收藏夹默认夹的做法）。**删前校验**：`GET /repos/{owner}/{repo}/compare/{branch}...{base}` 判断是否有未合并提交，有则阻止并提示。
  - ⚠️ **若删除的正是该仓库当前分支**：删除成功后按 §9.4.1 解析规则**回落 `defaultBranch`**，并失效该仓库的 contents/commits 缓存（否则会继续按已不存在的 `ref` 请求而 404）。
- 合并：`POST /repos/{owner}/{repo}/merges`。**冲突时 GitHub 返回 409**，且客户端无法解决 → 按 PRD 文案引导用户到网页端处理。

#### 9.7.2 PR 合并
`PUT /repos/{owner}/{repo}/pulls/{n}/merge`，`merge_method` 直接对应 PRD 的三种方式：

| UI 文案 | `merge_method` |
|---|---|
| Merge commit | `merge` |
| Squash and merge | `squash` |
| Rebase and merge | `rebase` |

- 合并失败常见原因：分支冲突（405/409）、未满足分支保护、无权限。需把服务端 `message` 转成可读提示。
- 合并成功后：PR 状态置 merged、**讨论锁定**（评论输入区整体隐藏）。

#### 9.7.3 Revert【已定 · 本期不在客户端实现】

**事实**：GitHub REST API 的 `commits` / `git` 端点清单中**没有 revert 端点**——网页端的 Revert 是服务端内部能力，未开放。（GraphQL 亦无对应 mutation。）

**客户端若自行实现的代价**（评估后决定不做）：

1. 需手工构造反向提交：取目标提交 → 取其父提交 tree → `POST /git/trees` → `POST /git/commits`（`parents: [当前 HEAD]`）→ `PATCH /git/refs/heads/{branch}`。**依赖 Git Data API 全链路**（而该链路已因 §9.6 不做暂存队列而不引入）。
2. **合并提交（merge commit）存在主线歧义**：多父提交需让用户选择 `-m` 保留哪条主线。
3. **无法干净反向的场景**：后续提交已依赖被回滚的改动时，反向 tree 会造成回退冲突。
4. 属**低频 + 高错误代价**操作：用户偶尔用一次，一旦构造错误会写坏分支历史。

**本期做法**：提交详情页**保留「↩ Revert 此提交（跳转网页端）」入口**，点击提示 `Revert 需在 GitHub 网页端完成` 并打开对应提交的网页地址。既不损失入口可发现性，也把高风险操作交给官方实现。

### 9.8 Issue 模块

| 功能 | 方案 |
|---|---|
| 列表（开放/已关闭） | `GET …/issues?state=`，⚠️ **必须过滤 `pull_request` 字段**（issues 端点会混入 PR） |
| 详情 | REST 两次请求（issue + comments）或 **GraphQL 一次聚合**（§4.6.5） |
| 新建 Issue | `POST …/issues`（title/body/labels）；标题为空时用占位标题（PRD 已定义） |
| 标签多选 | 仓库标签库 `GET …/labels`；选中集合存 ViewModel |
| 新建标签 | `POST …/labels`（`name` + `color`，**色值不带 `#`**）；重名 → GitHub 返回 422，客户端应提前本地去重并"已存在则自动选中" |
| 评论发送 | `POST …/issues/{n}/comments`；失败保留草稿（本地内存 + 可选持久化） |

**草稿策略**：发送失败时草稿必须保留供重试（PRD 已定义该错误态）。建议草稿落到本地存储，避免用户返回再进来丢失。

### 9.9 Pull Request 模块

- 详情头部：`GET …/pulls/{n}`；三态判定 = `state` + `merged_at`。
- **对话**：评论走 `GET/POST …/issues/{n}/comments`（PR 会话）；评审评论走 `GET …/pulls/{n}/comments`，含 `APPROVED` / `CHANGES_REQUESTED` 状态胶囊。
- **Commits**：`GET …/pulls/{n}/commits`，可点入提交详情（透传只读态）。
- **文件**：`GET …/pulls/{n}/files`，逐文件 `patch` → 解析为 `DiffCard`（§11.2）。PRD 明确指出的是"点击文件卡片展开 diff"，即**折叠态按需渲染**——正好配合 diff 解析的惰性化（大 PR 只解析可见文件）。
- **diff 原文兜底**：单文件 `patch` 缺失（大文件）时，可退回 PR 级 `application/vnd.github.diff` 并按文件切分。
- **操作区状态机**（对应 PRD §4.11）：

| 条件 | 可用操作 |
|---|---|
| 他人仓库 | 仅评论（提示无合并/关闭权限） |
| 自己的仓库 + open | 合并（三方式）/ 关闭 |
| 自己的仓库 + closed | 重新打开 |
| 自己的仓库 + merged | 无操作 + **隐藏评论输入区**（讨论已锁定） |

### 9.10 探索

#### 9.10.1 趋势取数（无官方 Trending API）【已定：双榜】

**问题**：GitHub 没有公开的 trending 端点，网页端 Trending 页是内部实现。本产品以 `GET /search/repositories` 近似，提供**两个榜单**（分段切换）。

| 榜单 | 查询 | 排序 |
|---|---|---|
| **新星榜** | `q=created:>=<90 天前> stars:>50` | 请求层 `sort=stars`；客户端可再用本地基线算出的"窗口内增幅"重排（§9.10.2） |
| **活跃榜** | `q=pushed:>=<窗口起点> stars:>50` | 客户端按 `pushed_at` 降序 |

- **两榜各一次 Search 请求**，采用**按需加载**（切到某榜才发起），并复用 ETag 条件请求缓存。
- **日期范围**（今天 / 本周 / 本月）→ 活跃榜直接作为 `pushed:` 起点；新星榜用于换算"新增 Star"的展示窗口。
- **编程语言** → `language:Swift` 等（GitHub Search **原生支持**）。
- `stars:>50` 为噪声兜底阈值（可调）。
- ⚠️ Search API 有**独立配额**（仓库 / 用户 / Issue 搜索 30 次/分钟，代码搜索约 10 次/分钟），且**结果上限 1000 条**（分页至 100 页），需缓存与节流。
- ⚠️ **"新增 Star 排序"不能由 Search 直接提供**——Search 只支持按总星 / Fork / 更新时间排序，真实增幅一律来自本地基线（§9.10.2）。首次见到某仓库时只记基线、不显示增幅。

#### 9.10.2 星增幅（本地基线）

**API 不提供 star 增速**。方案：本地维护 `StarSnapshotStore`（`{fullName: (stars, fetchedAt)}`）：

```
增幅 = 当前 stars − 上次快照 stars
按窗口换算：日 ≈ 周值/7、月 ≈ 周值×4.3（与 PRD 文案一致）
```

- 首次见到某仓库时**只记录基线、不显示增幅**（避免造数），UI 可显示"—"。
- 快照随趋势列表刷新而更新。

#### 9.10.3 榜单与筛选交互
- **榜单分段**：`ExploreBoard` 枚举（`rising` / `active`）驱动，切换即时刷新列表与标题，**不影响**已选筛选项。
- 两 chip 的空选语义（不选 = 全部、再点当前项 = 取消）由 ViewModel 状态驱动，UI 只反映状态。
- **筛选生效**：编程语言为真实过滤（`language:`）；日期范围对新星榜缩放"新增 Star"文案、对活跃榜限定 `pushed:` 窗口。

#### 9.10.4 交流语言：本期不实现【已定】

**决策**：探索页**只保留两个筛选项**——日期范围、编程语言。**不提供「交流语言」筛选。**

**依据（2026-10 官方文档核实）**：
- GitHub **REST 仓库搜索限定符清单中没有"交流语言"项**——官方限定符为 `in / repo / size / followers / forks / stars / created / pushed / language / topic / topics / license / is / props / mirror / template / archived / good-first-issues / help-wanted-issues / is:sponsorable / has:funding-file / deployable / deployed`，其中 `language:` 指**编程语言**。
- **GraphQL 的 `Repository` 类型同样没有该字段**。
- 该维度**只存在于 GitHub Trending 网页**，由 URL 参数 `spoken_language_code=<code>` 过滤。GitHub 官方客户端能用，是因为它是自家产品；**第三方 App 普遍靠抓取 Trending 页面 HTML 解析**（社区项目 `github-trending` / `github-trending-api` 均如此，解析 `div.Box article.Box-row` 结构后自建接口）。

**为何不选"抓取 Trending 网页"（被否方案）**：

1. **无 API 契约**：HTML 结构随时可变，一旦调整即全线失效，且没有版本协商、没有变更通知。
2. **数据源冲突（决定性）**：抓 Trending 得到的是 GitHub 内部算法排序的**另一套列表**（排序算法不公开，含 star 增速等内部权重），与基于 Search API 的新星 / 活跃双榜**不是同一批数据、也不是同一套排序**。若保留该筛选项，探索页会实质分裂成两个互不吻合的页面——一边是 Search 双榜，一边是 Trending 镜像，筛选与分页无法统一。
3. **与项目取向相悖**：本项目坚持零第三方依赖 + 只依赖有契约的官方接口，不引入依赖 HTML 结构的脆弱抓取。

**被否的其他方案**：

| 方案 | 被否原因 |
|---|---|
| 抓取 Trending 网页 | 无契约、易碎，且与双榜数据源冲突（见上） |
| 降级为 `topic:` 近似 | 语义有损；绝大多数仓库未标注此类 topic，实际筛不出结果 |

**影响面：无技术债。** 筛选项减一，`ExploreFilters` 仍为纯客户端状态；新星 / 活跃双榜 + 日期范围 + 编程语言**全部落在 Search API 之上，探索页数据通道保持单一**。若未来 GitHub 开放该维度，只需新增一个筛选项与一个限定符映射，不触及既有结构。

### 9.11 他人仓库详情（只读）

- 数据：`GET /repos/{owner}/{repo}` + `languages` + `releases/latest` + `contributors`。
- **只读是客户端行为**：可写权限来自 `permissions.push`；PRD 的"自己的仓库 / 他人仓库"分流即由此判定，而不是名称前缀。
- 语言构成：`GET …/languages` 返回 `{语言: 字节数}`，本地换算百分比并配语言色（需内置语言→色值映射表）。
- 分支切换弹层为只读模式（无"管理分支"入口）——由 `readOnly` 参数控制。
- README 渲染同 §11.1。

### 9.12 收藏夹与收藏项（纯本地）

- 数据：`Folder { name, isDefault }` + 收藏项映射 `favMap: [repoFullName: folderName]`（一个仓库**同时只属于一个**收藏夹），全部本地。
- ⚠️ **`count` 不是存储字段，而是从 `favMap` 推导**（`favMap` 中值等于该夹名的条目数）。**禁止**把它做成独立计数器——独立计数器在"换列表 / 取消收藏"时必然漏减，且与映射长期不一致（本项目原型第一版即踩此坑）。
- 两段式交互【已定】：首次点收藏 → 进默认收藏夹并提示"再点可选择列表"；已收藏后再点 → 打开选择列表弹层。
- **与 Star 完全解耦**：收藏不改 `starCount`、不进 Starred。产品文案已在 PRD 中明确"私人收藏夹，不影响 Star 数"。
- 注意：收藏项"是否已收藏"的判定需要仓库全名 → 收藏列表的索引，避免每次遍历。

**归属变更规则【已定】**（计数随之推导，PRD §6.2 有同一张表的产品口径）

| 动作 | 映射变更 | 计数效果 |
|---|---|---|
| 首次收藏 | `favMap[repo] = 默认夹` | 默认夹 +1 |
| 更换收藏夹 | 先移除、再写入 | 原夹 −1、目标夹 +1 |
| 取消收藏 | `favMap.removeValue(forKey: repo)` | 所属夹 −1 |
| 新建收藏夹并收藏 | 建夹 + 写入 | 新夹 +1、原夹 −1 |
| 重命名收藏夹 | 只改 `Folder.name` | **不变**（映射的"值"需同步改名，计数不受影响） |
| 删除收藏夹 | 其中的项 `favMap[repo] = 默认夹`，随后删夹 | 该夹整行消失；默认夹按回落条目数 +N |

- 对外只暴露 `move(repo:to:)` / `remove(repo:)` 两个方法，**计数永远由映射派生**，不存在"手工 +1/−1"的调用点。

**收藏夹管理页（`.folders`，PRD §4.19）**

- 纯本地增删改，**无任何网络请求**——收藏夹是 GitDuo 的私有概念，GitHub 没有对应资源（对照：置顶仓库有只读接口但无写接口 §4.6.1，本项连读接口也没有）。
- 三个动作的落点：

| 动作 | 实现要点 |
|---|---|
| 新建 | 名称 trim 后判空与重名；**重名不静默覆盖**，只提示不创建（与仓库页入口「提示并自动选中」区分开） |
| 重命名 | 输入框预填原名；trim 后判空、与**其它**收藏夹重名则拦截；与原名相同 ⇒ 直接关闭，不提示 |
| 删除 | 仅 `isDefault == false` 可删；二次确认弹层回显项目数并说明**收藏记录会回落到默认收藏夹（默认夹 +N）**；确认后先改归属再删夹（默认夹计数按回落条目数 +N，无悬空归属），提示 `已删除收藏夹「{名称}」· {N} 项已回落到「默认收藏夹」`，**不影响 Star 与仓库本身** |

- **默认收藏夹保护**：`isDefault == true` 的行不绑定任何动作（UI 不给入口 + 逻辑层二次拦截），保证"新收藏总有着落"。
- **单一数据源**：管理页与仓库详情页的「选择收藏列表」弹层读同一份 `FolderStore`；重命名 / 删除后两边都靠 `@Observable` 发布变更自动刷新。
- 若被删除的收藏夹正是某仓库当前的归属，该仓库**回落到默认收藏夹**，不产生"收藏到一个已不存在的列表"的悬空状态。

### 9.13 通知【本期不做】

**本期不实现**，决策与缘由见 §3.5.3。具体地：不新增通知 Tab、不实现未读角标与已读状态机、不请求 `GET /notifications` 全系列端点、不定义 `NotificationSource` 协议与 `Notification` 数据模型（不为"以后可能做"预留无用抽象）。

**若后续恢复时的既有结论**（保留供参考，本期不落地）：
- 未读计数与 Tab 角标联动（PRD §6.6）。
- 通知正文需按 `subject.url` **二次请求**（列表接口不返回正文），注意配额。
- ⚠️ 邮件通知 ≠ API 通知：用户在 GitHub 设置里关掉了 Web 通知就会没有数据，需在 UI 上给出来源说明。
- ⚠️ 该组端点仅支持 classic PAT（约束 2），恢复前需先确认此限制是否已解除。

### 9.14 我的

| 模块 | 方案 |
|---|---|
| 个人资料 | `GET /user` |
| 贡献热力图 | **GraphQL** `contributionsCollection.contributionCalendar` → 40 周 × 7 天网格，按 level 分 5 档配色；⚠️ 仅 GraphQL 提供 |
| 菜单 | Star 管理 / 我的收藏 / 我的 PR / 我的 Issue / 设置 |
| 我的 PR / Issue | `GET /search/issues?q=author:@me type:pr`（注意搜索配额） |
| 我的 Star | `GET /user/starred`；取消 Star = `DELETE /user/starred/{owner}/{repo}` 并联动计数 |
| 我的收藏 | **纯本地** `FolderStore`（§9.12）；不发请求 |

### 9.15 设置

| 项 | 方案 |
|---|---|
| 主题 | 本期仅 **浅色**，**不提供切换器**；颜色走语义 token（§10.7），补深色时只需补一列映射，不改 View |
| GitHub App · 账号 / 已授权 | 显示登录名 + 授权状态；**「退出登录」即程序化撤销 GitHub 侧授权**（§3.6）；保留"前往 GitHub 手动撤销"的网页跳转，作为撤销失败时的兜底入口 |
| 退出登录 | 二次确认弹层 → 清 Keychain 凭据 + 清账号绑定本地数据 + 重置导航栈 → 回登录页（详见 §3.8） |
| 清除缓存 | 统计 L2+L3 占用，一键清空并 Toast 反馈；⚠️ **保留 Keychain 凭据**，登录状态不变 |
| 版本 | 读 `CFBundleShortVersionString` + `CFBundleVersion` |

---

## 10. UI 与 Liquid Glass 实现规范

### 10.1 前提：iOS 27 起液态玻璃是默认基线，不可退出

【已定】用 Xcode 27 编译即自动采用 Liquid Glass，官方明确 **"opting out is no longer supported"**。因此它不是"要加的效果"，而是**设计必须成立的前提**。

随之而来的三个自带变化，设计须能承受：
1. 背景内容扩散更有效（可读性提升，但也更容易"透"）。
2. 新增**暗色边缘 + 更亮镜面高光**，层次分离更强。
3. 系统设置新增**用户可调滑块（极清透 ↔ 完全着色）** ⇒ 界面必须在两个极端下都成立。

### 10.2 铁律：玻璃只属于导航层，绝不进入内容层

> 官方原则：*Liquid Glass is exclusively for the navigation layer that floats above app content. Never apply to content itself (lists, tables, media).*

| 层级 | 本项目对应元素 | 处理 |
|---|---|---|
| **导航层（可玻璃）** | 底部 4 Tab、各页导航栏、工具栏、搜索图标按钮、探索页筛选 chip、仓库/PR 详情的底部操作条、Sheet | 系统组件**自动**玻璃；自定义控件显式加 |
| **内容层（必须实色）** | 仓库卡片、首页置顶卡片、Issue / PR 行、文件树行、评论区、README 正文、diff 卡片、代码块 | **一律实色，不得加玻璃** |

**落地规则**：
- 底部 Tab 用系统 `TabView`、页面用系统 `NavigationStack` 工具栏与 `Sheet` ⇒ **白送玻璃，不要自己画**。
- 需要自定义玻璃的只有：**搜索图标按钮**、**探索筛选 chip**、**底部操作条**三处。
- 反例警示：Apple 自家 Mail 是"正文实色、仅工具栏玻璃"——本项目卡片极多，这是最易做错的地方。

### 10.3 API 用法

```swift
// 单个自定义控件
.glassEffect(.regular.interactive(), in: .capsule)

// 着色（浅色约 30%、深色约 50% 混合）
.glassEffect(.regular.tint(.accentColor).interactive())

// 条件启用
.glassEffect(isEnabled ? .regular : .identity)

// 多个玻璃相邻：必须包容器
GlassEffectContainer(spacing: 12) {
    HStack { searchButton; filterChip; }
}

// 系统自带的玻璃按钮样式
.buttonStyle(.glass)          // 或 .glassProminent
```

- 形状：`.capsule` / `.circle` / `.rect(cornerRadius:)` / `RoundedRectangle(cornerRadius: .containerConcentric)`。
- 过渡：容器间距内用 `.matchedGeometry`，间距外用 `.materialize`。
- 变体：`.regular`（默认）/ `.clear`（需压暗层，适合媒体背景）/ `.identity`（禁用）。

### 10.4 七个已知坑与对策（必须防）

| # | 坑 | 现象 | 对策 |
|---|---|---|---|
| 1 | `.clipped()` / `.mask()` | **静默杀死玻璃**，降级为平铺材质且**无任何警告** | 玻璃控件不得嵌在会裁剪的容器内；需逃出滚动容器时用 `.overlay` / `.containerRelativeFrame` |
| 2 | `Form` | 行内 `.glassEffect` 是 **no-op** | 要玻璃就用 `List`，不用 `Form` |
| 3 | `GlassEffectContainer` 不跨 `NavigationStack` | 跨屏形变退化为淡入淡出 | 跨屏动画改用 `.navigationTransition(.zoom(...))` / iOS 27 的 `.crossFade` |
| 4 | 深浅色 tint 混合比例不同 | 品牌色偏深时深色模式近乎不透明 | 本期只做浅色；但**颜色必须走语义 token**（§10.7），深色补齐时无需返工 |
| 5 | `.interactive()` 仅 **A17 Pro+** | 旧设备静默降级为静态玻璃 | 接受降级；不做"是否支持"的显式判断 |
| 6 | 性能 | `.interactive()` 每帧多一次全屏采样；十几块玻璃滚动即掉帧 | **只给用户直接触摸的表面用**，绝不用作静态装饰 |
| 7 | 快照测试不稳定 | 镜面高光依赖模拟设备姿态 | 截图测试排除玻璃层或固定设备朝向 |

### 10.5 无障碍

- 系统**自动**响应「降低透明度」「增强对比度」「降低动态效果」⇒ **不要自己覆盖**（`@Environment(\.accessibilityReduceTransparency)` 仅在必要时使用）。
- 设计需同时成立的两个极端：极清透（背景几乎全透）与完全着色（近不透明）。
- 正文对比度以内容层为准（玻璃不承载正文，天然规避大部分对比度问题）。

### 10.6 iOS 27 顺带可用的新 API（对本项目有用）

| API | 用途 |
|---|---|
| `.crossFade` 导航过渡 | Tab 内推入页的柔和过渡 |
| `swipeActions` 支持**任意视图** | 列表行之外，卡片行也可左右滑（如 Star 列表取消 Star） |
| `AsyncImage` 缓存 | 头像与截图 |
| `toolbarMinimizeBehavior(:for:)` | 滚动时自动收起工具栏，给内容让位 |
| `@State` 对 `@Observable` 惰性初始化 | 减小首屏构造开销 |
| Swift 6.2 `-default-isolation MainActor` | App target 默认主 actor，显式 opt-in 并行 |

⚠️ 注意：UIKit 的 `UIGlassEffect` 与 SwiftUI 的 `.glassEffect()` **视觉不同步**，混用需审计。本项目**纯 SwiftUI**，不受影响——这也是坚持不引入 UIKit 桥接的理由之一。

### 10.7 设计系统

- 颜色、字号、间距、圆角统一收敛到 `GitDuoDesign` 的令牌；**禁止在 View 内写魔法值**。
- 状态色沿用 GitHub 语义（开放=绿、已合并=紫、已关闭=红、已发布=紫），与 PRD 一致。
- 玻璃用法封装为组件（`GlassIconButton` / `GlassChip` / `GlassActionBar`），业务代码不直接写 `.glassEffect`，从机制上防止误用。

**颜色令牌的硬约束【已定 · 为深色模式预留】**

本期**只交付浅色**，但所有颜色**必须**定义为语义 token，**禁止任何 View / 资源里出现写死色值**：

| 要求 | 说明 |
|---|---|
| 语义命名 | 按用途命名（`textPrimary` / `textSecondary` / `surface` / `surfaceRaised` / `border` / `accent` / `stateOpen` …），**不按色相命名**（禁止 `gray600`、`blue500`） |
| 单一来源 | 每个 token 在 `GitDuoDesign` 内集中定义一次；浅色是本期的唯一实现，深色只需补一列映射 |
| 系统语义色优先 | 能用系统语义色（`.primary` / `.secondary` / `.tint`）的地方直接用，减少自建 token |
| 玻璃 tint | 玻璃着色值也走 token（浅色约 30% 混合，深色约 50%，见 §10.4 #4） |

**为什么现在就约束**：Liquid Glass 在深浅色下 tint 混合比例不同（约 30% / 50%），且需同时成立"极清透 ↔ 完全着色"两个极端（§10.5）。若本期写死色值，补深色时需**全量返工并逐页重新校准对比度**；走 token 则只是一次映射表的补充。

**已知偏差 · 三级文字对比度【已定 · 2026-10-05】**

`textTertiary`（`#8B949E`，取自原型）在两种底色上的对比度：

| 底色 | 对比度 | 门槛（WCAG 2.1 大字号） | 结论 |
|---|---|---|---|
| 卡片面 `#FFFFFF` | ≥ 3.0 | 3:1 | ✅ 达标 |
| 页面底 `#F6F8FA` | **2.89:1** | 3:1 | ⚠️ **差 0.11，登记后接受** |

**决策：保留现值，不调整。** 理由：① 该 token 只用于时间戳等**极弱辅助信息**；
② 调色等于改产品视觉，而**原型是唯一可点验收依据**，改 token 必须同步改原型；
③ 0.11 的差距属工程噪声级，不影响实际可读性。

**护栏**：`GitDuoDesignTests.ThemeTests.tertiaryTextContrast` 已固化为「页面底 **≥ 2.85**」的下界断言——
将来任何调色若低于此值会使测试失败，届时必须连同本偏差一并重新评估。

**若将来要求达标**：把 `#8B949E` 加深至 `#6E7781` 一类（约 3.2:1），但**必须同步修改 `redesign/prototype/styles/01-base.css` 的 `--text3`** 并回写 PRD §7。

---

## 11. 自研渲染模块（零第三方依赖）

### 11.1 Markdown 块级渲染

| 项 | 方案 |
|---|---|
| 目标 | 把 Markdown 转成 `AttributedString`，**块级感知**（标题/段落/列表/引用/代码块/表格） |
| 支持范围 | 标题、段落、有序/无序列表（含嵌套）、引用、行内代码、代码块（带语言）、链接、粗斜体、分隔线、任务列表 |
| 输出 | `AttributedString` + 自定义 `AttributedStringKey`（块类型、缩进层级、代码语言） |
| 渲染 | SwiftUI `Text` 承载富文本；代码块单独用等宽视图 + 横向滚动 |
| 不做 | 内嵌 HTML、脚注、数学公式、复杂的表格嵌套（超出本期范围） |

**注意**：`AttributedString(markdown:)` 系统能力对块级结构支持有限，需自研解析器补足（按行扫描 → 块类型判定 → 行内解析），并用单测覆盖边界（嵌套列表、代码块内的 `#`、未闭合标记等）。

### 11.2 unified diff 解析

| 项 | 方案 |
|---|---|
| 输入 | `patch` 文本（`@@ -a,b +c,d @@` 格式）或 `application/vnd.github.diff` 原文 |
| 输出 | `[DiffHunk] → [DiffLine]`，行类型：上下文 / 新增 / 删除，含新旧行号 |
| 边界 | 无换行结尾标记 `\ No newline at end of file`、多文件分割（`diff --git`）、二进制文件（`Binary files … differ`）、`\r\n` |
| 渲染 | 等宽字体 + 行号列（不可选中）+ 红/绿底色；hunk 头单独一行 |
| 性能 | **按需解析**：折叠状态下不解析；展开时才解析该文件。大 PR（数百文件）必须惰性化 |

### 11.3 语法高亮

| 项 | 方案 |
|---|---|
| 范围 | 先支持少量高频语言（Swift / Rust / TypeScript / Python / Go / JSON / Markdown），其余降级为纯文本 |
| 方式 | 轻量词法着色（关键字 / 字符串 / 注释 / 数字 / 函数名），非完整语法分析 |
| 性能 | 逐行着色 + 结果缓存；只对**可见区域**着色（长文件必须分段） |
| 与玻璃的关系 | 代码块属**内容层**，实色背景，不走玻璃 |

---

## 12. 并发与可测试性

### 12.1 并发模型

| 层 | 隔离方式 |
|---|---|
| View / ViewModel | `@MainActor`（App target 可开 `-default-isolation MainActor`） |
| Repository / Service | `Sendable` 类型，方法 `async`；无状态或仅持有 actor 引用 |
| CacheStore / TokenStore / RateLimiter | `actor`（串行化共享可变状态） |
| DTO / Domain Model | `Sendable` 值类型（`struct` + `let`） |

**硬性要求**：
- 令牌刷新必须 **single-flight**（§3.2），否则并发 401 会引发刷新竞争。
- 缓存读写不得阻塞主 actor。
- 所有跨 actor 传递的类型必须 `Sendable`，编译期由 Swift 6 严格并发检查保证。
- 任务取消要贯通（搜索防抖、页面退出时的在途请求）。

### 12.2 测试策略

| 类型 | 覆盖 | 工具 |
|---|---|---|
| 单元测试 | Mapper、diff 解析、Markdown 块解析、语言构成百分比换算、星增幅换算、权限判定、状态机（认证三态、PR 三态、收藏两段式）、收藏夹规则（默认夹不可改删 / 重名不覆盖 / 删除后回落默认夹）、**分支解析规则**（记忆命中 / 分支已删 ⇒ 回落 `defaultBranch` / 无记忆 / 两个仓库互不影响，§9.4.1）、**收藏计数推导**（收藏 / 换列表 / 取消 / 删夹回落，且计数恒等于映射派生值）、**授权回调校验**（`state` 不匹配 / 重复回调 / 非 `oauth/callback` 形状一律丢弃） | Swift Testing |
| 网络层测试 | 用 `URLProtocol` 桩件断言：请求头（版本号/Bearer/If-None-Match）、分页解析、401→刷新→重放、304 处理、限流识别、GraphQL body.errors | Swift Testing + 自定义 `URLProtocol` |
| 认证流程测试 | PKCE 生成（`code_challenge` = BASE64URL(SHA256(verifier))）、`state` 不一致必须拒绝、取消不落凭据、换令牌失败不留半成品、刷新 single-flight、退出登录后本地数据与栈被清空 | Swift Testing |
| 集成测试 | TokenStore 往返、缓存 LRU 淘汰、本地存储持久化、`FolderStore` 读写与跨页一致性、**计数恒由 `favMap` 派生**（收藏 / 换夹 / 取消 / 删夹回落后，各夹计数与归属条目数恒等，无独立计数器可漂移） | Swift Testing |
| UI 测试 | 关键路径：未登录启动→登录页→授权→进首页；退出登录→回登录页；进入仓库→切分区→切分支→编辑→提交；搜索四范围；PR 合并三方式；我的收藏→重命名 / 删除 / 新建；**跨仓库分支互不影响**（A 切分支 → 进 B 显示 B 的默认分支 → 回 A 仍是原分支） | XCUITest |
| 快照测试 | ⚠️ **排除玻璃层**或固定设备朝向（§10.4 #7） | 自建或 `swift-snapshot-testing`（若引入则为**测试期**依赖，不影响运行时零依赖） |

---

## 13. 性能与配额预算

### 13.1 首屏预算

| 指标 | 目标 |
|---|---|
| 冷启动 → 首页可交互 | ≤ 1.5s（含令牌恢复；首页数据本地优先、网络异步补齐） |
| Tab 切换 | 无网络等待（各自栈已缓存） |
| 列表滚动 | 稳定 60fps；玻璃单元数量受控 |

### 13.2 典型页面配额成本（REST 请求数 + GraphQL 点数）

**REST（`core` 桶 5,000 请求/小时，每请求 1 单位）**

| 操作 | 请求数 | 备注 |
|---|---|---|
| 打开仓库详情（代码分区） | 1（repo）+ 1（contents） | README 另计 1 |
| 提交流程（新分支 + PR） | 3–4 | refs → contents → pulls |
| 搜索（边输边搜） | ≥1/次输入 | **必须防抖**，否则 30/min 秒破 |

**Search 桶（独立配额，与 `core` 分开计）**

| 端点 | 配额 | 本项目谁在用 |
|---|---|---|
| `GET /search/repositories` | **30 次/分钟** | **探索页双榜**、搜索页「仓库」范围 |
| `GET /search/users` | 30 次/分钟 | 搜索页「用户」范围 |
| `GET /search/issues` | 30 次/分钟 | 搜索页「Issue · PR」范围；我的 PR / Issue |
| `GET /search/code` | **约 10 次/分钟** | 搜索页「代码」范围（🔻 仅默认分支、≤384KB、需 ≥1 非限定词） |

⚠️ **探索页是 Search 桶的高频入口，单独预算**（风险 #6 此前只覆盖代码搜索）。两榜各用一次 `search/repositories`，且**每次切榜 / 切筛选都会触发一次**，因此：

| 交互 | 请求数 | 说明 |
|---|---|---|
| 首次进入探索（默认新星榜） | 1 | 只拉当前榜，不预取另一榜 |
| 切换榜单（新星 ↔ 活跃） | 0–1 | 已拉过 ⇒ 命中缓存 0 次；首次切过去 1 次 |
| 切换筛选（日期 / 语言） | 0–1 | 缓存键 = `榜 · 日期范围 · 编程语言`，同键 0 次 |
| 下拉刷新 | 1 | 显式刷新才失效缓存（ETag 命中 304 时仍不计配额） |
| 「加载更多」 | 1/页 | 结果上限 1000 条（≈10 页即到底，§9.10.1） |

**预算与纪律**：

1. **缓存键必须含全部筛选维度**（榜 · 日期 · 语言）——漏一个维度就会退化成"每次切换都请求"。
2. 切榜 / 切筛选做 **≥300ms 防抖**，并**取消前一个在途请求**（与搜索页同一套取消策略）。
3. 理论最坏值：用户连点榜单与筛选，1 分钟内最多 `2 榜 × 3 日期 × 6 语言 = 36` 种组合 ⇒ **必须靠缓存与取消压住**，否则单是探索页就能吃掉 30/min 的全部额度并连带把搜索页拖下水（同一个 Search 桶）。
4. 命中缓存 / 304 的切换**不消耗配额**——这正是探索页"秒切"的来源。

**GraphQL 点数（`graphql` 桶 5,000 点/小时；按官方公式预扣，与实际返回条数无关）**

官方计点公式：**点数 = round（Σ 完成调用中每个唯一连接所需的请求数 ÷ 100），最小 1 点**。嵌套连接**相乘**（父连接 `first` × 子连接 `first`），因此点数取决于查询的**潜在最大节点数**，而非真实返回量——"多返回几条"不额外扣费，"多嵌套一层"却会成倍扣费。官方示例：`repositories(first:100)` → 1，其下 `issues(first:50)` × 100 → 100，再其下 `labels(first:60)` × 5,000 → 5,000，合计 5,101 → **51 点**。

| 场景 | 连接结构（`first` 上限） | 潜在请求数 | 预扣点数 |
|---|---|---|---|
| 首页置顶（≤6 个） | `viewer.pinnedItems(first:6)`，仅取标量字段，**不嵌套连接** | 1 | **1** |
| 贡献热力图 | `viewer.contributionsCollection.contributionCalendar.weeks(first:53)`（`contributionDays` 是数组，**不构成连接**） | 1 | **1** |
| Issue 详情聚合 | `repository.issue`（单对象）+ `comments(first:100)` + `timelineItems(first:100)` | 3 | **1** |
| PR 详情聚合 | 同上，另加 `reviews(first:100)`——四个连接挂在**同一个单对象下、互不相乘** | 4 | **1** |
| ⚠️ PR 详情（**误写成乘性嵌套**） | 若在 100 条评论**元素下各再开一个**连接（如 `reactions(first:100)`） | 4 + 100×100 | **100** |

> 上表最后一行是本项目最需要防的反面案例：**同样的"一个查询"，只因多写了一层嵌套，点数从 1 涨到 100**——这就是"按潜在最大节点数预扣"的实际含义。

**预算与纪律（列入代码审查清单）**

1. **单查询硬上界**：潜在请求数 ≤ **500**（即 ≤ **5 点**）；超出即**拆分为多个查询**，优先游标分页（`after:`）而非加大 `first`。
2. **禁止"集合元素下再开连接"**：这是点数唯一的乘性来源（`50 × 20 × 10 = 10,000` → 单次直接扣 100 点）。嵌套连接层级 ≤ 3 层，且**不在第二层集合的元素内再开连接**。
3. `first` 取**该列表首屏实际条数**（20 / 30），不图省事写 100。
4. **开发期**用 `rateLimit { cost }` 校对预估值；**运行期**读响应头 `x-ratelimit-remaining` / `x-ratelimit-resource: graphql`（§4.5）。
5. 单次调用**总节点数 500,000** 是 schema 硬上限（超出直接拒），与点数无关，但它决定绝对天花板。

**结论**：四个 GraphQL 场景在**不嵌套集合**的前提下**全部只需 1 点**（最多 4 个连接也仍是 1 点），5,000 点/小时的理论容量在 5,000 次量级，**远非瓶颈**；真正的风险不是"用得多"，而是**一次错误的乘性嵌套**——同一个查询多写一层，点数就从 1 跳到 100，故纪律 1、2 必须逐条核对。

### 13.3 配额保护

- 条件请求默认开启；写操作后精准失效相关缓存。
- 搜索类独立限流（Search 桶，§13.2），代码搜索串行。
- **探索页**：缓存键含全部筛选维度、切榜 / 切筛选防抖 300ms + 取消在途请求——它与搜索页**共用同一个 Search 桶**，放任会把搜索一起拖垮。
- 可选：设置页暴露剩余配额（`GET /rate_limit`）。

---

## 14. 安全与隐私

| 项 | 措施 |
|---|---|
| 凭据存储 | 仅 Keychain；`AfterFirstUnlockThisDeviceOnly` |
| 凭据传输 | 仅发往 `api.github.com` / `github.com`；**绝不**发往第三方或自有服务 |
| `client_secret` | **内嵌进 App 是平台强制**（官方 Required，且不区分 public / confidential 客户端，§3.1）；定位为**软机密**：挡得住随手薅、**挡不住反编译**。只允许出现在「换令牌 / 刷新 / 撤销」三条请求里，**不进日志、不进崩溃上报、不进任何缓存**；文件本体 git-ignored。⇒ **用户数据安全不依赖它**：取出 secret 仍需过 PKCE + 用户本人在系统浏览器内授权，**拿不到任何已有用户的令牌**（§3.7 / §15 #17） |
| 授权界面 | 用 `ASWebAuthenticationSession`（系统浏览器），不用内嵌 `WKWebView` |
| 授权回调 | 回调**只承载 `code` 与 `state`，绝不承载令牌**；`state` 一次性校验；兑换令牌的 `code_verifier` 仅存内存（PKCE）——使被动劫持者即使拿到 `code` 也无法兑换（§3.9） |
| 授权交互 | **拒绝静默授权**（不用 `prompt=none` / 已授权自动跳过），用户必然在系统浏览器中看到 GitHub 授权页并明确同意 |
| URL scheme | 自定义 scheme **不是安全边界**（任何 App 均可声明同一 scheme）；已登记抢注 / 劫持四类场景、残余风险与 Universal Link 收敛方向（§3.9） |
| 无后端收益 | 不存在"用 GitHub 令牌换自家凭证"的风险面 |
| 日志 | 令牌、仓库内容不得进日志与崩溃上报；生产构建关闭详细网络日志 |
| 剪贴板 | Raw 内容复制为显式用户动作；不自动写入剪贴板 |
| 隐私 | 无自建后端 ⇒ 无服务端数据留存；本地数据可一键清除（登出 / 清除缓存） |

---

## 15. 风险登记表

| # | 风险 | 影响 | 等级 | 应对 |
|---|---|---|---|---|
| 1 | ~~通知能力与 GitHub App 不兼容~~ | — | **已关闭** | **本期不做通知**：移除 Tab 与全部通知端点，平台级矛盾随之消失（§3.5.3） |
| 2 | ~~Watch 订阅可能不受支持~~ | — | **已关闭** | 本期 Watch **仅展示计数**，不调用订阅端点，无需实测（§3.5.2） |
| 3 | **探索趋势无官方 API** | 趋势榜为近似，非 GitHub 官方 Trending | 中 | 双榜各用 Search 限定符（`created:` / `pushed:`）+ 本地基线算增幅（§9.10.1） |
| 4 | ~~交流语言无对应字段~~ | — | **已关闭** | **本期不实现该筛选项**：探索页只保留日期范围 + 编程语言，数据通道保持单一（§9.10.4） |
| 5 | ~~Revert 无原生端点~~ | — | **已关闭** | **本期不在客户端实现**：入口保留并跳转网页端，不构造反向提交，无需 Git Data API（§9.7.3） |
| 6 | 搜索配额极紧（代码 10/min；仓库 / 用户 / Issue 各 30/min，**四类共用一个 Search 桶**） | 频繁搜索被限流 | 中 | 防抖 + 取消 + 串行 + 结果缓存 |
| 7 | Liquid Glass 误用到内容层 | 界面失焦、可读性下降 | 中 | 玻璃组件统一封装 + 逐控件清单（§10.2） |
| 8 | `.clipped()` 静默杀死玻璃 | 效果莫名失效且无警告 | 中 | 代码审查清单 + 快照验证（§10.4 #1） |
| 9 | GraphQL 错误在 200 响应体 | 静默失败 | 中 | 强制解析 `body.errors`，纳入网络层测试 |
| 10 | Issues 端点混入 PR | 列表数据错误 | 低 | 一律按 `pull_request` 字段过滤 |
| 11 | ~~无后端 ⇒ 无法程序化撤销授权~~ | — | **已关闭** | **决策 #30（内嵌 secret）后已可程序化撤销**：`DELETE /applications/{client_id}/grant` 对 `ghu_` 令牌同样适用，且失败不阻塞登出（§3.6） |
| 12 | 404 与"无权限"混同 | 错误文案误导 | 低 | 统一文案"不存在或无权访问"（§4.3） |
| 13 | ~~权限清单缺 `Starring` / `Followers`~~ | — | **已关闭** | **补齐 2 项账号级权限**（决策 #25）：Star / 取消 Star、Starred 分段、关注 / 取关不再 403（§3.4） |
| 14 | ~~安装页漏选「全部仓库」~~ | — | **已关闭** | **登录页固定引导选 All repositories**（决策 #26），并在 403 / 404 文案指向授权范围（§3.5.4） |
| 15 | **自定义 URL scheme 被抢注 / 回调被劫持** | 授权码外泄；极端场景（攻击者自建授权会话）可被兑换 | 中 | PKCE + 一次性 `state` 挡住被动劫持与伪造回调；**拒绝静默授权、scheme 不承载深链**；根治需 Universal Link，本期登记为残余风险（§3.9 / §16 未来工作） |
| 16 | **探索页吃满 Search 桶** | 切榜 / 切筛选每次都发 `search/repositories`，会把**与搜索页共用的 30/min** 挤掉，表现为"搜索突然 403" | 低 | 缓存键含全部筛选维度 + 切榜防抖 300ms + 取消在途请求；已单独预算（§13.2），命中缓存 / 304 不耗配额 |
| 17 | **`client_secret` 内嵌进包的"软机密"** | 反编译可取出，可被用来冒充本 App 发起授权 / 撤销请求 | 中 | **平台无解**（官方强制 secret，且不区分 public / confidential 客户端，§3.1）；缓解：只用于「换令牌 / 刷新 / 撤销」三条请求 + 不进日志与崩溃上报 + 文件 git-ignored + **用户数据安全不依赖它**（取出 secret 仍拿不到任何已有用户的令牌，还需过 PKCE 与用户本人在系统浏览器内的授权）。**登记为已接受的残余风险**（§3.7 / §14） |
| 17 | **分支记忆跨仓库串用** | 从 A 仓库切到 `feature/x` 后进 B 仓库，B 若没有该分支则行为未定义（列表空、请求 404） | 低 | 分支按仓库分别记忆 + 进入时校验存在性，失效回落 `defaultBranch`（决策 #28，§9.4.1）；`Repository.defaultBranch` 必须有值 |

---

## 16. 开放问题（待确认）

**无。** 技术侧与产品侧的开放问题已全部闭环，可以直接进入工程搭建。

**已全部关闭的项**（留档，勿再作为开放问题）：

| 曾经的开放问题 | 结论 | 出处 |
|---|---|---|
| 收藏夹管理页 | **新增独立管理页**「我的 → 我的收藏」，支持新建 / 重命名 / 删除；内置默认收藏夹不可改删 | §9.12 |
| 登录 / 授权页的产品定义 | **已定义**：未登录全屏门禁 + 登录页（6 项权限预告）+ GitHub 授权页（6 条清单）；取消与失败出口齐备 | §3.8 |
| 权限清单是否够用 | **补 `Starring`(RW) 与 `Followers`(RW)** 共 6 项：Star / 取消 Star、Starred 分段、关注 / 取关都依赖它们 | §3.4 |
| 令牌可见范围（安装范围） | **安装页须引导选「全部仓库」**：GitHub App 令牌 = 用户权限 ∩ App 权限 ∩ 安装仓库范围 | §3.5.4 |
| 通知处置路线 | **本期整体不做** | §3.5.3 |
| Watch 订阅是否可用 | 本期**仅展示计数**，不调用订阅端点 | §3.5.2 |
| `client_secret` 怎么处理（原 D4） | **内嵌持有**（**决策 #30**）：官方 Required 且不区分 public / confidential 客户端，官方对 native app 的建议即"打进包里 + 用 PKCE"；附带解锁"登出可程序化撤销授权"（§3.6） | §3.1 / §3.6 / §3.7 |
| 探索趋势取数策略 | **新星榜 + 活跃榜双榜** | §9.10.1 |
| 「交流语言」筛选 | **不实现**（公开 API 无此维度） | §9.10.4 |
| Revert 实现路径 | **不在客户端实现**，入口跳网页端 | §9.7.3 |
| 首页置顶数据源 | **只读同步 GitHub 个人主页**（GraphQL `pinnedItems`）；客户端不提供增删，「管理」跳网页端 | §9.1 |
| 提交暂存队列 | **不做** ⇒ 不引入 Git Data API | §9.6 |
| App 标识 / 回调 scheme | **`gitduo://oauth/callback`** | §3.7 |
| URL scheme 仿冒 / 劫持 | **已评估并登记**：自定义 scheme 非安全边界；采用 PKCE + 一次性 `state` + 回调不携带令牌 + 拒绝静默授权 + scheme 不承载深链；残余风险与收敛方向见 §3.9 与本节「未来工作」 | §3.9 |
| 加载态 / 骨架屏 | **三档统一**：骨架屏 / 行内指示 / 按钮内联 loading | §8.5 |
| 分页交互 | **混合**：普通列表自动加载，搜索用「加载更多」 | §4.4 |
| 深色模式 | **本期不做**，颜色走语义 token 预留 | §10.7 |
| 多账号切换 | **本期不做**，命名空间已预留 | §7.2 |

**未来工作（记录收敛方向，不构成本期开放问题）**

| 项 | 前置条件 | 价值 |
|---|---|---|
| 回调换用 claimed HTTPS（Universal Link） | 一个可控域名 + 能静态托管 `apple-app-site-association` | 根除自定义 scheme 的抢注与静默授权劫持（§3.9 场景 A / C） |
| 回调 scheme 改反域名形式（`com.<org>.gitduo://oauth/callback`） | 下一次改动 App 标识时顺带 | 符合 RFC 8252 §7.1；**不能**解决场景 C，仅提升规范性 |

> 以上两项均为**平台约束下的收敛方向**，本期登记为已知残余风险（§3.9），不影响开工与交付。

---

## 附录 A：API 端点总表（按资源）

| 资源 | 读 | 写 |
|---|---|---|
| 当前用户 | `GET /user` | — |
| 仓库 | `GET /user/repos` · `GET /repos/{o}/{r}` · `GET /users/{u}/repos` | — |
| Star | `GET /user/starred` ◇ | `PUT/DELETE /user/starred/{o}/{r}` ◇ |
| Watch | `GET /repos/{o}/{r}/subscription`（仅计数） | —（本期不做订阅，§3.5.2） |
| Fork | — | `POST /repos/{o}/{r}/forks` |
| 关注 | `GET /user/following/{u}` ◇ | `PUT/DELETE /user/following/{u}` ◇ |
| 内容 | `GET /repos/{o}/{r}/contents/{path}` · `GET …/readme` | `PUT /repos/{o}/{r}/contents/{path}` |
| Git Data | `GET …/git/trees/{sha}` · `GET …/git/blobs/{sha}` | ❌ 写操作本期不引入（`blobs` / `trees` / `commits` / `refs` → 仅在暂存队列或大文件上传时才需要，§9.6） |
| 分支 | `GET …/branches` | `POST …/merges` |
| 提交 | `GET …/commits` · `GET …/commits/{sha}` | ⚠️ Revert 无原生端点 |
| Issue | `GET …/issues` · `GET …/issues/{n}` · `GET …/issues/{n}/comments` · `GET …/labels` | `POST …/issues` · `PATCH …/issues/{n}` · `POST …/issues/{n}/comments` · `POST …/labels` |
| PR | `GET …/pulls` · `GET …/pulls/{n}` · `…/files` · `…/comments` · `…/commits` | `PUT …/pulls/{n}/merge` · `PATCH …/pulls/{n}` · `POST …/pulls` · `POST …/pulls/{n}/reviews` |
| Release | `GET …/releases/latest` | — |
| 洞察 | `GET …/languages` · `GET …/contributors` | — |
| 搜索 | `GET /search/repositories` · `/search/users` · `/search/code` 🔻 · `/search/issues` | — |
| 通知 | **本期不做**（§3.5.3） | — |
| GraphQL | `pullRequest` · `issue` · `contributionsCollection` · `viewer.pinnedItems` | — |

🔻 = 仅默认分支、文件 <384KB、需 ≥1 非限定词、≈10 请求/分钟
◇ = 需**账号级权限** `Starring`(RW) / `Followers`(RW)；缺权限时 `GET /user/starred` 只返回公开部分（§3.4）
⚠️ **以上全部端点另受「令牌可见范围」约束**：可见范围 = 用户权限 ∩ App 权限 ∩ 安装时勾选的仓库（§3.5.4）

## 附录 B：能力 × 权限矩阵（客户端行为）

| 能力 | 自己的仓库 | 他人仓库 | 判定依据 |
|---|---|---|---|
| 浏览 / 文件 / README | ✅ | ✅（只读） | — |
| 分支切换浏览 | ✅ | ✅（无管理） | `readOnly` |
| 新建 / 删除 / 合并分支 | ✅ | ❌ | `permissions.push` |
| 新建 / 编辑 / 上传文件 · 提交 · Revert | ✅ | ❌ | `permissions.push` |
| 新建 / 关闭 Issue · 标签 | ✅ | ❌（仅评论） | `permissions.push` / `triage` |
| 合并 / 关闭 PR | ✅ | ❌（仅评论） | `permissions.push` / `maintain` |
| Star / Fork / 收藏 | ✅ | ✅ | — |
| Watch（仅展示计数） | ✅ | ✅ | 本期不调用订阅端点 |

---

*本文档为 GitDuo 2.0 技术设计说明（v1.0，待评审）。功能口径以 `PRD.md` v1.0 为准。*
