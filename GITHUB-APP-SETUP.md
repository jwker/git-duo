# GITHUB-APP-SETUP —— GitHub App 配置手册

> **谁做**：只有你能做（GitHub 侧，代码层无解）——即 `REVIEW-CHECKLIST.md` 的前置条件 **P1 / P2 / P3 / P5**。
> **耗时**：约 10 分钟。**做完的效果**：切片 1（Auth）一写完就能真跑。
> **事实来源**：GitHub 官方文档，**2026-10-05 逐条核对**（链接见 §10）；本项目的口径见 `TECH_SPEC.md` §3。
> ⚠️ 先说一句：官方文档里**有三条事实和本项目现有文档冲突**，其中一条必须现在就修正（见 §0）。请先读 §0 再动手。

---

## 0. ⚠️ 动手前必读：三条官方事实，与现有文档冲突

### 0.1 ⚠️ 换令牌**强制要求 `client_secret`**（已拍板：**内嵌持有**，§9 方案 A）

官方《为 GitHub 应用生成用户访问令牌》参数表里，**`client_secret` 标为 Required**（必需），
即使携带了 PKCE 的 `code_verifier` 也没有例外：

> `client_secret` **string** **Required.** The client secret for your GitHub App.

而 2025-07-14 的 PKCE 官方公告明确说了原因：

> GitHub is not requiring PKCE for any authentication flow at this time, **as GitHub does not distinguish between public and confidential clients.**

**即：GitHub 不区分 public / confidential 客户端，因此不存在"用 PKCE 换掉 secret"这条路。**
GitHub 给 native app 的官方建议是**把 secret 打进包里 + 用 PKCE**（《创建 GitHub App 的最佳实践》原文）：

> If your app is a public client (a native app that runs on the user's device, CLI utility, or single-page web application), **you cannot secure your client secret. You will have to ship the client secret in the application's code, and you should use PKCE** to better secure the authentication flow.

**影响面**（共 8 处现有文字曾以此为前提，**已全部改毕**，清单见 §9）：

| 位置 | 现有文字 |
|---|---|
| `TECH_SPEC.md:88` | 「无后端 ⇒ 必须 PKCE」段 |
| `TECH_SPEC.md:201` | 步骤 6「**不带 client_secret**」 |
| `TECH_SPEC.md:305` | 「不持 secret ⇒ **无法程序化撤销**」 |
| `TECH_SPEC.md:315` | 参数表「`client_secret` \| **不存入客户端**」 |
| `AGENTS.md:81` | 铁律 9「`client_secret` **永不进入客户端**」 |
| `PRD.md:265` | 「安全：客户端不持有 client secret」 |
| `redesign/prototype/scripts/13-auth.js:38` | 登录页 fnote「客户端内嵌的 secret 属"软机密"」 |
| `GitDuo/App/AppConfig.swift:7,31` | 注释同上 |

**结论（2026-10-05 用户拍板）**：**采用方案 A —— 内嵌 `client_secret` + PKCE**，即 GitHub 官方建议。
定位为**软机密**：挡得住随手薅、**挡不住反编译**；**PKCE + 一次性 `state` 仍是主防线**，不因有 secret 而放松。
附带解锁**登出可程序化撤销授权**（§9.1）。三个方案的取舍见 §9。

### 0.2 🔴 **不要勾** "Request user authorization (OAuth) during installation"

现有 `Secrets.xcconfig.example` 与 `REVIEW-CHECKLIST.md` P3 都让你勾这项，**这是错的**。官方文档原文：

> **If you want to control which callback URL is used, do not select Request user authorization (OAuth) during installation.** Instead, direct users through the full web application flow and specify the `redirect_uri` parameter.

勾了之后 GitHub 会在安装完直接把用户送到 `https://github.com/login/oauth/authorize?client_id=<你的 Client ID>`——
**没有 `state`、没有 `code_challenge`、且强制使用列表里的第一个回调 URL**。后果：
- 一次性 `state` 校验失效 → 我们的 CSRF 防线（§3.9）没了；
- PKCE 根本不会生效（授权请求里没带 challenge，`code_verifier` 无从校验）；
- 无法指定 `redirect_uri`。

⇒ **保持不勾**，由 App 自己发起带 `state` + PKCE 的完整授权请求。（安装是另一步，见 §4。）

### 0.3 🟡 刷新令牌：`client_secret` 是"必需的例外"

官方《刷新用户访问令牌》参数表原文：

> `client_secret` **string** **Required unless the user access token was generated using the device flow.**

⇒ **只有 device flow 拿到过令牌，刷新才不需要 secret**。这正好是方案 A / B 的分水岭：
方案 A 下，刷新也要把 secret 带在包里；方案 B 下才真正零 secret。

---

## 1. 配置前的准备

| 项 | 说明 |
|---|---|
| GitHub 账号 | 用来**创建并拥有**这个 App（应用归属可以是个人账号，也可以是组织） |
| 归属选择 | 本期建议挂**个人账号**，最省事；将来要团队共管再迁组织 |
| 决定 App 名 | 小写化、空格转 `-`、特殊字符替换后得到 **slug**（`GitDuo` → `gitduo`），安装链接即 `https://github.com/apps/<slug>/installations/new`；名字**全局唯一**且 ≤34 字符（规则与出处见 §2.1） |
| 决定安装范围 | `Only on this account`（只有你能装）还是 `Any account`（任何人可装，公开发布的前提） |

---

## 2. 逐步配置（严格按 GitHub 表单顺序）

创建入口：**https://github.com/settings/apps/new**
（或：头像 → Settings → Developer settings → GitHub Apps → New GitHub App）

### 2.1 GitHub App name

- 填 **`GitDuo`**；若被占用，用 `GitDuo-<你的用户名>`。
- **长度**：≤ **34** 字符；**必须全局唯一**。官方原文：
  > The name cannot be longer than 34 characters. ... **The name must be unique across GitHub.** You cannot use the same name as an existing GitHub account, unless it is your own user or organization name.
- **slug 从哪来**（官方原文，同一段）：
  > Your app's name (**converted to lowercase, with spaces replaced by `-`, and with special characters replaced**) will be shown in the user interface when your app takes an action. For example, `My APp Näme` would display as `my-app-name`.

  ⇒ 上面那个"转换后的小写串"就是 **slug**（`GitDuo` → `gitduo`），它决定了
  `https://github.com/apps/<slug>` 这个**安装链接**（§4.2）。
- ⚠️ **把 slug 当"一次性定死"的东西**：官方《修改 App 注册》只写了「可以更改 name / description / homepage」，
  **没有说明 slug 会不会跟着变**（第三方说法不一，不足为据）。
  ⇒ 结论：**别依赖改名后 URL 是否不变**；要改名就改完**回设置页核对 Public link**，再决定旧链接是否还有效。

### 2.2 Description（可选）
- 建议：`GitDuo —— 用 SwiftUI 写的第三方 GitHub 客户端`。用户安装时会看到。

### 2.3 Homepage URL（**必填**）
- 没有官网时，官方允许填**代码仓库地址或账号地址** ⇒ 填 `https://github.com/<你的用户名>`。

### 2.4 Callback URL —— **本项目最关键的一栏**

```
gitduo://oauth/callback
```

| 要点 | 说明 |
|---|---|
| 自定义 scheme 可用吗 | **可以**。官方在 `prompt` 参数说明里明确提到「应用具有**非 HTTP 重定向 URI**」的情形；业界同类产品（如 Flutter/Serverpod 系）标准做法就是 `com.example.yourapp://auth` |
| 能填几个 | 最多 **10** 个（`Add callback URL`） |
| 必须精确匹配 | **新建 App 的通配匹配默认关闭**（通配是 2026-08-03 前只配了一个回调 URL 的应用才默认开启），因此 `redirect_uri` 必须**逐字符相同**，且**不能带任何附加参数** |
| 大小写 / 斜杠 | 一律按注册值原样比对 —— 注册 `gitduo://oauth/callback`，请求里就得是这一串 |
| 与项目代码的对应 | `AppConfig.callbackURL` = `"gitduo://oauth/callback"`；`project.yml` → `Info.plist` 已注册 scheme `gitduo` |

> ⚠️ **回调 URL 是对外契约**（TECH_SPEC §3.9）：这一栏改动必须**同时**改 `AppConfig.swift`、`project.yml`、PRD/TECH_SPEC。
> （§16 里还留着一个未采纳的收敛方案：改成反域名 `io.github.<你>.gitduo://oauth/callback`，安全性不提升、只是规范性更好，**本次不做**。）

#### 2.4.1 三个 URL 别混：各自带什么参数

整套流程里出现三个不同的 URL，**注册的这一栏恰恰是最"素"的那个**：

| # | URL | 出现在哪 | 参数 |
|---|---|---|---|
| 1 | `gitduo://oauth/callback` | **注册表单**（§2.4）· `AppConfig.callbackURL` | **一个都没有**。`oauth/callback` 是 **path**，不是参数。注册值**不得带 `?` 及其后任何东西**，否则请求里的 `redirect_uri` 永远对不上（§7 第 1 行） |
| 2 | `https://github.com/login/oauth/authorize?...` | **App 代码**（`TECH_SPEC` §3.1 步骤 3） | `client_id`（**必需**）· `redirect_uri`（**必须与注册值逐字符相同**）· `state`（一次性随机串，防 CSRF）· `code_challenge`（verifier 的 SHA-256，43 字符 base64url）· `code_challenge_method=**S256**`。可选：`login`（指定账号）、`allow_signup`、`prompt=select_account` |
| 3 | `gitduo://oauth/callback?code=...&state=...` | **回调时**由 GitHub 拼出来 | `code`（一次性，10 分钟过期）· `state`（原样回传，**必须与步骤 2 发出的比对**）。App 要解析这两个，但**注册值和请求参数里都不写它们** |

> 关键区分：**#1 是"门牌号"，#2 是"敲门时说的话"，#3 是"门里递出来的东西"。**
> 只有 #2 需要写参数，而 #2 的 `redirect_uri` 必须等于 #1。
>
> 另：我们的回调是**非 HTTP 重定向 URI**，官方说明此时 GitHub 会**自动弹出账号选择器**（即使用户只登录了一个账号），
> 因此**不需要**手动传 `prompt=select_account`。

### 2.5 ☑ Expire user authorization tokens —— **保持勾选**（默认就是勾的）

- 官方："GitHub recommends that you opt in to this feature for improved security."
- 勾上才有：`ghu_` 令牌 **8 小时**过期 + `ghr_` 刷新令牌 **6 个月**。
- **这正是我们 `TECH_SPEC` §3.7「401 → 刷新 single-flight」设计的前提** ⇒ 必须勾。
- ⚠️ 不勾的后果：令牌**永不过期**，一旦泄漏无法靠时间收口。

### 2.6 ☐ Request user authorization (OAuth) during installation —— **不要勾**

理由见 **§0.2**（会绕过 `state` 与 PKCE，并锁定第一个回调 URL）。
不勾的代价：安装与授权分成两步（安装见 §4），比"一步到位"多一次点击——**换来的是 §3.9 的整套防护**。

### 2.7 ☐ Enable Device Flow —— **只有选方案 B 才勾**

- 它是无外设/CLI 环境的产物。官方最佳实践**明确反对**在有浏览器、有回调的客户端上启用：
  > **do not enable the device flow** for your application unless you are using the app in a constrained environment
- 勾了之后还要注意：device flow **不使用 PKCE**（官方公告原文），登录页要改成"显示 8 位 user_code + 让用户去 github.com/login/device 输入"——**原型那一屏要重做**。

### 2.8 Post installation
- **Setup URL 留空**（本项目无网页端，没有"安装后说明页"；且若勾了 2.6，这一栏会直接不可填）。
- **Redirect on update 忽略**（Setup URL 为空时该项无效）。

### 2.9 Webhook —— 把 **Active 取消勾选**
- 官方："if your app will only be used for authentication or does not need to respond to webhooks, **deselect this option**."
- 本项目**零后端**，没有接收 webhook 的服务器；开启它只会带来无效投递失败告警。
- 连带：**Webhook URL / Secret / SSL verification 全部不用填**；`Subscribe to events` 也**一个都不要勾**。

### 2.10 Permissions —— 只勾这 7 项（6 项申请 + 1 项强制）

表单里权限分两组，逐项用下拉框设成下表的值。**其余全部留 `No access`。**

**Repository permissions（仓库权限）**

| 权限 | 设为 | 支撑的能力（PRD） |
|---|---|---|
| **Contents** | **Read and write** | 代码 / 文件树浏览、新建 / 上传 / 编辑文件、提交、分支管理（§4.4–§4.8） |
| **Issues** | **Read and write** | Issue 列表 / 详情 / 新建 / 关闭 / 评论 / 标签（§4.9） |
| **Pull requests** | **Read and write** | PR 列表 / 详情 / diff / 评论 / 合并 / 关闭（§4.10、§4.11） |
| **Metadata** | Read-only（**强制，灰显改不了**） | 仓库基本信息与列表的底座权限，GitHub 要求所有 App 必选 |

**Account permissions（账号权限）**

| 权限 | 设为 | 支撑的能力（PRD） |
|---|---|---|
| **Starring** | **Read and write** | Star / 取消 Star、Starred 列表、首页双榜里的 Star 分段（§4.1、§4.14、§4.18） |
| **Followers** | **Read and write** | 关注 / 取关、粉丝与关注列表（探索页他人主页、个人主页） |

> ⚠️ **`Starring` / `Followers` 是最容易漏的两项**（它们在 Account permissions 组，不在仓库组）。
> 漏了不会报错，只会在 Star / 关注时收到 **403**——这是 `REVIEW-CHECKLIST.md` P2 专门标注过的坑。

> 🔴 **而这两项还有一个独有的坑（2026-10-09 查得）：勾上了也不一定生效 —— 已授权的旧令牌不会自动获得。**
> 官方《Approving updated permissions for a GitHub App》原文：
>
> > **If the app is authorized but not installed or if the GitHub App only requested additional account permissions,
> > GitHub will not notify you. Instead, the GitHub App will prompt you to reauthorize the app in order to enable the new account permissions.**
>
> 拆开看，这句话对**账号级**权限说了三件事，每一件都会让人查错方向：
> ① **GitHub 不会通知你**（仓库级权限才有通知）⇒ 你**收不到任何提示**说"权限升级了"；
> ② 旧令牌**继续有效**（官方另一句：*If you do not approve the additional permissions, the GitHub App will still retain its current permissions*）
> —— 所以**登录、看仓库全都正常**，只有 Star 这一处 403，表现得像"这一颗按钮坏了"；
> ③ 唯一的修法是**重新走一遍授权流程**拿到**新令牌**（官方 user-level 权限那段：*you will, however, need to send existing users
> through the user authorization flow to authorize the new permission and get a new user-to-server token for these requests*）。
>
> ⇒ **"授权页列出 6 条"（P2 过了）与"手里这张令牌带 Starring"是两件事**：
> 前者看的是 App **当前的声明**，后者是**授权那一刻**的快照。**两者不一致时，屏幕上只看得见后者。**

> 🔴 **而"权限名勾了"与"级别够了"又是第三件事（2026-10-09 补）**：`Starring` 这一项的下拉框有
> **Read-only** 与 **Read and write** 两个值。⚠️ **授权页只列权限名、不列级别** ⇒ "目视 6 条"这一手
> **看不出级别**。而这一层的症状极好认、也极容易被读错方向：
>
> | 症状 | 说明 |
> |---|---|
> | **读**正常（详情页显示「已 Star」）、**写** 403 | 令牌有 `Starring` 的读、缺写 ⇒ **声明就是 Read-only** |
> | **读**也不通（按钮显示 `Star`） | 令牌里根本没有 `Starring` ⇒ 上一条那个"旧令牌"的情形 |
>
> 分辨它的价值：**"改声明"与"换令牌"是两个动作**，猜错一个就白跑一轮。逐条处置见 §7。
> （这正是走查 #3 那条 403 最可能的成因，处置步骤见 `REVIEW-CHECKLIST.md` 清单 C 的 P2 段。）

> **为什么不需要 Email addresses / Profile**：本期界面不展示邮箱，资料页只用登录名与头像。
> 若将来要显示邮箱，需补 `Email addresses`(Read-only) 并让已安装用户重新批准。

### 2.11 Where can this GitHub App be installed?
- **`Only on this account`**：只有你（及该组织的成员）能安装。**本期推荐**——半成品不该被陌生人装上。
- **`Any account`**：任何人可装。将来要给别人用、或想用**第二个 GitHub 账号**验证时改成它（**改这一项零成本，随时可切**）。

### 2.12 点 **Create GitHub App** ✅

---

## 3. 创建后：抄下三样东西

App 设置页（`https://github.com/settings/apps/<slug>`）上：

| 项 | 位置 | 用途 | 是否要抄 |
|---|---|---|---|
| **App ID** | 页面中部 | JWT / 安装令牌（本项目**不用**这些流程） | ❌ 不用 |
| **Client ID** | 页面中部 | 授权请求的 `client_id`（**注意：不是 App ID**） | ✅ **要** |
| **Client secret** | 「Generate a new client secret」按钮 | 换令牌 / 刷新令牌 / **登出撤销授权**（§9.1） | ✅ **要**（方案 A 已采纳） |
| **slug** | 设置页 URL 里 `/apps/<slug>`（即「**Public link**」字段） | 拼安装链接（§4.2） | ✅ 要（但**不进代码**，见 §3.1） |

> 🔑 **Client secret 只在生成的瞬间显示一次**（关掉页面就再也看不到，只能重新生成）。
> ⚠️ 它是**"软机密"**：方案 A 下它会被打进 `.ipa`，**必须能被反编译取出**——所以它保护的是"顺手薅"而不是"有备而来"。
> **它不是本仓库的机密**，但**仍然禁止入库**（`.gitignore` 已挡 `Secrets.xcconfig`）。

### 3.1 四个标识别混，且只有一个进代码

App 设置页上并排出现四样东西，**名字听起来都像"身份"，但用途完全不同**：

| 标识 | 长什么样 | 用在哪 | 进本项目代码吗 |
|---|---|---|---|
| **App name** | 人类可读（`GitDuo`），也是 `/apps/<slug>` 的来源 | 只用于展示 | ❌ |
| **slug** | 小写串（`gitduo`），即 URL 里的名字 | **拼安装链接**（§4.2）；API 的 `/app` 响应里也有 `slug` 字段 | ❌ **不进** |
| **App ID** | 纯数字（如 `123456`） | 私钥签发 JWT、安装令牌流程 | ❌ 本项目不用这些流程 |
| **Client ID** | `Iv1.` 之类的字符串 | **授权请求的 `client_id`**、换令牌 | ✅ **唯一要写进 `Secrets.xcconfig` 的** |

> **slug 只在你手工拼安装链接时用一次，从头到尾不出现在 GitDuo 的代码里**
> （`AppConfig.swift` 只有 `clientID` 与 `callbackURL`）。
> ⇒ 它写错不会导致登录失败，**只会导致安装链接打不开**——两者的报错完全不同，别混着查。

---

## 4. 安装 App —— 决定"能看见哪些仓库"的一步

### 4.1 "安装"到底是什么意思

GitHub App 有**三件互相独立的事**，OAuth App 只有其中两件：

| # | 动作 | 在哪做 | 产出 | 谁做 |
|---|---|---|---|---|
| ① | **创建 App** | github.com/settings/apps/new | 一个 App 身份：`Client ID` + 声明的权限 + 注册的回调 URL | 你（App 所有者）**已做** |
| ② | **安装 App**（installation） | `github.com/apps/<slug>/installations/new` | 把 App **挂到某个账号 / 组织上**，并**选定它能访问哪些仓库** | 你（作为安装者）**待做** |
| ③ | **授权 App**（authorization） | App 内的登录页发起 | 一张 **`ghu_` 用户令牌**（代表"你"） | 你（作为用户）**待做** |

**为什么 ② 不能省**——官方《迁移指南》原文：

> If you want your GitHub App to make API requests on behalf of itself **or access organization or repository resources, the user must install your GitHub App.** When a user installs a GitHub App on their account or organization, **they choose which repositories the app can access**, and they grant the app the organization and repository permissions that it requested.

也就是说：**App 访问仓库的能力是以"installation"为单位授予的**。
只创建不安装 ⇒ App 在 GitHub 眼里"没有挂到任何地方" ⇒ 令牌照样能拿到，
但请求仓库接口时**列表里什么都没有**（不是 403，是压根不出现）。

这正是 GitHub App 区别于 OAuth App 的地方：OAuth App 一授权就拿到"你能访问的全部"，
GitHub App 多一道**安装时选仓库**的闸门——**多一步操作，换来的是更小的暴露面**。

> ⚠️ 组织账号安装时，**组织内的每个成员还要各自授权**（官方原文：*each user within that organization must authorize the app in order for the app to act on their behalf*）。
> 本期只有你一个账号、且 App 挂在个人账号下，所以是"装一次 + 授权一次"。

### 4.2 操作步骤

打开安装页：

```
https://github.com/apps/<slug>/installations/new
```

1. 选账号（个人 / 组织）→ **Install**。
2. **Repository access 选 `All repositories`** ✅
   —— 原型登录页那行加粗提示就是这个意思。
3. 点 Install 完成。

**令牌可见范围公式**（`TECH_SPEC` §3.5.4）：

> **令牌可见范围 = 用户权限 ∩ App 权限 ∩ 安装时勾选的仓库**

只勾了部分仓库 ⇒ GitDuo 里**永远看不到**其余仓库。
用户若选了 `Only select repositories`，必须在设置页把新仓库补进安装范围。

> 之后改安装范围：`https://github.com/settings/installations` → 找到 GitDuo → Configure。

### 4.3 安装 URL 能带哪些参数（**本项目全都不用**）

官方支持两种带参形式，但**都不适用于本项目**，列出来是为了让你日后看到别人的文档时不困惑：

| 形式 | 参数 | 用途 | 本项目为何不用 |
|---|---|---|---|
| `/installations/new?state=<串>` | `state` | 把状态**原样带回**，用于在安装完成后把用户送回 App 的某个页面（官方："以保留应用页面的状态"） | 回传依赖 **Setup URL**，而我们的 Setup URL 留空（无网页端，§2.8）⇒ **没有接收点**，传了也没人看 |
| `/installations/new/permissions?suggested_target_id=<ID>&repository_ids[]=<ID>` | `suggested_target_id`（该形式下**必需**）· `repository_ids[]`（最多 100 个，省略=全选） | **OAuth App → GitHub App 迁移专用**：预选旧 OAuth App 已能访问的仓库 | 我们没有旧 OAuth App 要迁移 |

> 🔑 **`state` 只在授权流程里承担安全职责**（§6 第 1 项那个 `.../authorize?state=...`），
> 安装流程里的 `state` 纯属"页面状态保持"，**与防 CSRF 无关**。两者别混。

---

## 5. 填进本地工程

编辑仓库根目录下的 **`Secrets.xcconfig`**（git-ignored；模板见 `Secrets.xcconfig.example`），**两项都要填**：

```
GITDUO_CLIENT_ID = <粘贴 Client ID>
GITDUO_CLIENT_SECRET = <粘贴 Client secret>
```

> ⚠️ 只填 `client_id` 会在**换令牌**那一步失败（§0.1）；两项都由 `project.yml` 注入 `Info.plist`，工程侧无需再改。

然后重新生成工程并验证注入是否生效：

```bash
make gen && make build
/usr/libexec/PlistBuddy -c "Print :GitDuoClientID" \
  build/DerivedData/Build/Products/Debug-iphonesimulator/GitDuo.app/Info.plist
/usr/libexec/PlistBuddy -c "Print :GitDuoClientSecret" \
  build/DerivedData/Build/Products/Debug-iphonesimulator/GitDuo.app/Info.plist
```

（`AppConfig.isConfigured` 会在值为空或 `REPLACE_ME` 时返回 `false`，登录页据此给出明确提示而不是发一个注定失败的请求。）

---

## 6. 配置自检清单（配完跑一遍，5 项）

| # | 检查 | 期望结果 |
|---|---|---|
| 1 | 打开授权页（把 `<Client ID>` 换掉）：`https://github.com/login/oauth/authorize?client_id=<Client ID>&redirect_uri=gitduo%3A%2F%2Foauth%2Fcallback&state=test&code_challenge=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx&code_challenge_method=S256` | 页面列出的权限清单 = **6 条**，且与原型登录页预告的 6 项**一字不差**（授权页由 GitHub 按 App 配置渲染，此处不符 = 权限勾错了） |
| 2 | Callback URL 是否精确匹配 | 授权后 GitHub 跳转到 `gitduo://oauth/callback?...`（若报 `redirect_uri_mismatch` 见 §7） |
| 3 | 令牌有效 | `curl -s -H "Authorization: Bearer <令牌>" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2026-03-10" https://api.github.com/user` → 返回你的 `login` |
| 4 | 安装范围生效 | 同上令牌请求一个**私有仓库** `/repos/<owner>/<repo>` → 200（404 见 §7） |
| 5 | Starring 权限生效 | `curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Authorization: Bearer <令牌>" https://api.github.com/user/starred/<owner>/<repo>` → **204**（403 = 漏勾 Starring） |

> 第 1 项能对上，说明**权限**配对了；第 3–5 项能对上，说明**令牌**配对了。

> ⚠️ **第 3–5 项都要一个 `<令牌>`，而 App 里那张令牌在 Keychain 里、你拿不出来** ⇒ 配完想复核时容易卡在这一步。
> 不必卡：**重新走一遍授权**就是这三项的最强证据 —— 新令牌是按 App **当前**声明签发的，
> 所以"重新登录后 Star 通了"这件事，同时证明了第 1 / 3 / 5 项（`REVIEW-CHECKLIST.md` 清单 C 的 P2 段有完整步骤）。
> 想真的跑 curl，就得自己走一次 §6 的授权流程手工把 `code` 换成令牌（`code` **10 分钟过期、一次性**）。

### 6.1 ⚠️ 两个"看起来能验、其实验不了"的坑（2026-10-06 实测证伪）

配完凭据后，很容易想用命令行"先验一下 `client_id` 对不对"——**这两条路都是死路**，实测数据如下：

| 想验什么 | 试过的办法 | 实测结果 | 结论 |
|---|---|---|---|
| `client_id` 是否有效 | `curl` 那个 authorize 端点看响应码 | 有效 id / `Iv1.0000…` 假 id / `totally-bogus-id` → **一律 302 跳 `/login`** | ❌ 响应码不携带有效性信息 |
| `X-GitHub-Api-Version` 是否被接受 | 带版本头请求 `/zen` | `2026-03-10` / `2025-01-01` / `2022-11-28` → **一律 200** | ❌ 该端点不校验版本头 |
| 同上（换受保护端点） | 带版本头请求 `/user`（无令牌） | 有效版本 / `2027-99-99` 假版本 → **一律 401** | ❌ 鉴权前就短路，轮不到校验 |

**唯一能判断 `client_id` 是否配对的，只有第 1 项**——登录后看授权页**实际渲染出的权限清单**（那是 GitHub 按你的 App 配置生成的，对不上就是配错了）。

> `X-GitHub-Api-Version: 2026-03-10`（`AppConfig.apiVersion`）的最终确认，留到切片 2 拿到真令牌后用 `/user` 实测：400 = 版本头无效，401/200 = 通过。

---

## 7. 常见坑速查

| 现象 | 原因 | 处理 |
|---|---|---|
| `redirect_uri_mismatch` | 请求里的 `redirect_uri` 与注册值不完全一致 | 逐字符比对 §2.4；注意 URL 编码（`gitduo://oauth/callback` → `gitduo%3A%2F%2Foauth%2Fcallback`），且**不要带附加参数** |
| `incorrect_client_credentials` | `client_id` / `client_secret` 写错（如误用了 App ID） | 用设置页上的 **Client ID**，两者不同 |
| `bad_verification_code` | `code` 过期（**10 分钟**）或已用过 | 重新发起授权；`code` 一次性 |
| Star / 关注 **403** | 漏勾 `Starring` / `Followers` | §2.10 勾上；**改权限后已安装用户需重新批准** |
| 🔴 **写** Star 报 `操作失败 · 请重试`，而**读**一切正常（仓库详情页那颗按钮显示的是 **`已 Star`**、不是 `Star`） | 令牌带着 `Starring` 的**读**、却缺**写** ⇒ ### App 申报的级别是 **Read-only**（或者这张令牌是"级别还是 Read-only"那会儿签发的）。依据：官方对这个端点写的是 *"The fine-grained token must have the following permission set: **`Starring` user permissions (write)**"*，而"查有没有 Star 过 / 列 Starred 列表"只要 **read** ⇒ **读得到、写不了，正好是级别不够的形状** | ① App 设置页 → **Permissions & events** → *Account permissions* → **`Starring`** 改成 **Read and write**；② **再**在 GitDuo 里**退出登录 → 重新登录**（改声明 ≠ 换令牌，见 §2.10 那条 🔴） |
| Star **连"读"也不通**（详情页那颗按钮显示 `Star` 而不是 `已 Star`；「我的 Star」列表空 / 失败） | 令牌里**完全没有** `Starring`：授权发生在权限变更**之前**。⚠️ **账号级**权限（`Starring` / `Followers`）变更时 GitHub **既不通知、旧令牌也不会自动获得**（§2.10 那条 🔴）⇒ 登录 / 浏览全正常，只有 Star 这一处 403 | **在 GitDuo 里退出登录 → 重新登录**（重走授权 ⇒ 拿到含 `Starring` 的新令牌）。**这一步零成本，先做它** |
| ✅ **已排除（2026-10-09，实测）**：请求形状 | 官方对 `PUT /user/starred/{o}/{r}` 有一句 *"you'll need to set `Content-Length` to zero when calling out to this endpoint"* ⇒ 怀疑过我们那条**无 body 的写请求**（`HTTPTransport.makeURLRequest` 在 `body == nil` 时不设 `Content-Length`）。**本地 socket 抓包实测：`URLSession` 自己就会发 `Content-Length: 0`**（`PUT` / `DELETE` 都一样） | 不必改 `HTTPTransport`；同时说明"写失败"**不是**请求组装的问题，别在这条路上再花时间 |
| 重新授权后 Star **仍然** 403 | 先回到上一格看"**读**通不通" —— 那一步能把两种成因分开 | a) App 声明**逐项核对级别**（授权页只列**名字**、不列级别 —— §6 那次目视看不出这一层）；b) curl 看**响应体**与 **`X-Accepted-GitHub-Permissions`** 响应头（官方：权限不足回 403，该头会说明端点要什么）；c) 若**只有私有仓库**失败 ⇒ §4 的安装范围（但那更该是 404） |
| 仓库相关 **404**（而非 403） | GitHub 对**无权限**的资源返回 404 以隐藏存在性；也可能是没安装 / 没勾该仓库 | 查 §4 的安装范围；`/user/installations` 可看当前可访问仓库 |
| 换令牌返回的是 `access_token=ghu_...` 这种**表单串**而不是 JSON | 没带 `Accept: application/json` | 请求头加上 `Accept: application/json` |
| 刷新报 `unsupported_grant_type` | `grant_type` 没写 `refresh_token` | 官方要求 `grant_type=refresh_token` |
| 已安装用户突然不好用 | 改了权限或回调 URL | 权限变更需用户在 `https://github.com/settings/apps/authorizations` 重新批准 |

---

## 8. 以后要动这些设置时

| 改动 | 后果 |
|---|---|
| 改 **Callback URL** | 对外契约变更 ⇒ 同时改 `AppConfig.swift` / `project.yml` / PRD / TECH_SPEC；已登录用户需重新走授权 |
| 增删 **Permissions** | 已安装用户**必须重新批准**；且要同步改 PRD §6.1、原型 `AUTH_PERMS`（harness 有"登录页预告 ≡ 授权页清单"的逐条一致断言，改一边就会红） |
| 改 **App name** | 官方**未说明 slug 是否联动** ⇒ 改完回设置页核对 **Public link**；若 slug 变了，已分享的安装链接失效。**代码不受影响**（slug 不进代码，见 §3.1） |
| 切 **Only on this account ↔ Any account** | 零成本，随时可切 |

---

## 9. D4 决策记录：`client_secret` —— ✅ **已拍板：方案 A（内嵌 + PKCE）**（2026-10-05）

| 方案 | 做法 | 代价 | 与现有资产的关系 |
|---|---|---|---|
| **A ✅ 已采纳** | 内嵌 `client_secret` + PKCE | secret 可被反编译取出（"软机密"）；GitHub 官方明确认可这是 public client 的做法 | **原型/文档的授权码流程完全不用改**，只改 8 处措辞（§0.1 表）+ `Secrets.xcconfig` 多一行 |
| B | 启用 Device Flow，不生成 secret | UX 退化（8 位 user_code + 手动输入）；**官方反对**；**原型登录页/授权页那一屏要重做** | 改动最大：§3.1 流程重写 + 原型重做 + harness 登录段断言重写 |
| C | 加一个极薄中继（如 Cloudflare Worker，免费）换令牌 | 违背 `TECH_SPEC` 决策「**无后端**」（决策 #5），需要维护一个域名与服务 | 文档决策表要改；工程侧反而更简单 |

**拍板理由**：GitHub 自己的文档就是这么建议 public client 的；
「客户端不持 secret」这一前提**在 GitHub 上从来无法成立**（不区分客户端类型）；
而 B 会让 §3.9 那套 `state` + PKCE 防护与原型整屏作废，C 则要推翻"零后端"这条已定决策。

**已落地**（完整清单见 `REVIEW-CHECKLIST.md` §5 D4）：`TECH_SPEC` 决策表 **#30** + §1.2 / §1.3 / §3.1 / §3.2 / §3.6 / §3.7 / §3.8 / §9.15 / §14 / §15 / §16；
`AGENTS.md` 铁律 9；`PRD` §4.0.1 / §5.11 / §8；原型登录页与退出登录弹层；`AppConfig` + `project.yml` + `Secrets.xcconfig(.example)`。

### 9.1 方案 A 附带解锁：登出可**程序化撤销**授权

因为客户端现在持有 `client_secret`，`DELETE /applications/{client_id}/grant`
（Basic Auth = `client_id` : `client_secret`）变得可用，且官方明确该组端点**对 `ghu_` 令牌同样适用**：

> Tokens for OAuth apps have the prefix `gho_`, while OAuth tokens for GitHub Apps… have the prefix `ghu_`. **You can use the following endpoints for both types of OAuth tokens.**

⇒ 「退出登录」从**"只清本地 + 引导用户去网页手动撤销"**升级为**"先撤销 GitHub 侧授权，再清本地"**。
撤销失败（离线 / 422）**不阻塞登出**，仅提示降级。细节见 `TECH_SPEC` §3.6。

> ⚠️ 注意区分：**撤销授权（authorization）≠ 卸载 App（installation）**。撤销后 installation 仍在，
> 重新登录只走授权流程、**不需要重新安装**。

---

## 10. 官方来源（2026-10-05 核对）

| 内容 | 链接 |
|---|---|
| 注册 GitHub App（表单逐栏说明） | https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app |
| 用户授权回调 URL（多回调 / 通配匹配） | https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/about-the-user-authorization-callback-url |
| 生成用户访问令牌（授权参数 + 换令牌参数） | https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app |
| 刷新用户访问令牌（`client_secret` 的 device flow 例外） | https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens |
| 最佳实践（public client 应内嵌 secret + PKCE；慎用 device flow） | https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/best-practices-for-creating-a-github-app |
| PKCE 支持公告（不区分 public / confidential） | https://github.blog/changelog/2025-07-14-pkce-support-for-oauth-and-github-app-authentication/ |
