# GITHUB-APP-SETUP —— GitHub App 配置手册

> **谁做**：只有你能做（GitHub 侧，代码层无解）——即 `REVIEW-CHECKLIST.md` 的前置条件 **P1 / P2 / P3 / P5**。
> **耗时**：约 10 分钟。**做完的效果**：切片 1（Auth）一写完就能真跑。
> **事实来源**：GitHub 官方文档，**2026-10-05 逐条核对**（链接见 §10）；本项目的口径见 `TECH_SPEC.md` §3。
> ⚠️ 先说一句：官方文档里**有三条事实和本项目现有文档冲突**，其中一条必须现在就修正（见 §0）。请先读 §0 再动手。

---

## 0. ⚠️ 动手前必读：三条官方事实，与现有文档冲突

### 0.1 🔴 换令牌**强制要求 `client_secret`**（与本项目"客户端不持 secret"的前提冲突）

官方《为 GitHub 应用生成用户访问令牌》参数表里，**`client_secret` 标为 Required**（必需），
即使携带了 PKCE 的 `code_verifier` 也没有例外：

> `client_secret` **string** **Required.** The client secret for your GitHub App.

而 2025-07-14 的 PKCE 官方公告明确说了原因：

> GitHub is not requiring PKCE for any authentication flow at this time, **as GitHub does not distinguish between public and confidential clients.**

**即：GitHub 不区分 public / confidential 客户端，因此不存在"用 PKCE 换掉 secret"这条路。**
GitHub 给 native app 的官方建议是**把 secret 打进包里 + 用 PKCE**（《创建 GitHub App 的最佳实践》原文）：

> If your app is a public client (a native app that runs on the user's device, CLI utility, or single-page web application), **you cannot secure your client secret. You will have to ship the client secret in the application's code, and you should use PKCE** to better secure the authentication flow.

**影响面**（共 8 处现有文字与此前提绑定，均需在拍板后改）：

| 位置 | 现有文字 |
|---|---|
| `TECH_SPEC.md:88` | 「无后端 ⇒ 必须 PKCE」段 |
| `TECH_SPEC.md:201` | 步骤 6「**不带 client_secret**」 |
| `TECH_SPEC.md:305` | 「不持 secret ⇒ **无法程序化撤销**」 |
| `TECH_SPEC.md:315` | 参数表「`client_secret` \| **不存入客户端**」 |
| `AGENTS.md:81` | 铁律 9「`client_secret` **永不进入客户端**」 |
| `PRD.md:265` | 「安全：客户端不持有 client secret」 |
| `redesign/prototype.html:1816` | 登录页 fnote「客户端不持有 client secret」 |
| `GitDuo/App/AppConfig.swift:7,31` | 注释同上 |

**三个可选方案（**需你拍板，见 §9**）**：
**A（推荐）** 内嵌 secret + PKCE —— 即 GitHub 官方建议，改动最小，与原型的授权码流程一致；
**B** 改用 device flow —— 真·零 secret（刷新也不需 secret），但 UX 变差且**官方明确反对**（无需回调 URI ⇒ 易被钓鱼冒充）；
**C** 薄中继（Cloudflare Worker 之类）—— secret 不出服务器，但**违背"零后端"目标**。

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
| 决定 App 名 | 名字会转成小写 + 连字符作为 **slug**，安装链接就是 `https://github.com/apps/<slug>/installations/new`，**必须唯一** |
| 决定安装范围 | `Only on this account`（只有你能装）还是 `Any account`（任何人可装，公开发布的前提） |

---

## 2. 逐步配置（严格按 GitHub 表单顺序）

创建入口：**https://github.com/settings/apps/new**
（或：头像 → Settings → Developer settings → GitHub Apps → New GitHub App）

### 2.1 GitHub App name
- 填 **`GitDuo`**；若被占用，用 `GitDuo-<你的用户名>`（≤34 字符，全局唯一）。
- ⚠️ 名字决定 slug（`GitDuo` → `gitduo`）⇒ 决定安装链接。**改名会改 slug**，已分享的安装链接即失效。

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
| **Client secret** | 「Generate a new client secret」按钮 | 换令牌 / 刷令牌（**方案 A 才需要**） | 方案 A ✅ / 方案 B ❌ |
| **slug** | 页面 URL 里 `/apps/<slug>` | 拼安装链接（§4） | ✅ 要 |

> 🔑 **Client secret 只在生成的瞬间显示一次**（关掉页面就再也看不到，只能重新生成）。
> ⚠️ 它是**"软机密"**：方案 A 下它会被打进 `.ipa`，**必须能被反编译取出**——所以它保护的是"顺手薅"而不是"有备而来"。
> **它不是本仓库的机密**，但**仍然禁止入库**（`.gitignore` 已挡 `Secrets.xcconfig`）。

---

## 4. 安装 App —— 决定"能看见哪些仓库"的一步

打开安装页：

```
https://github.com/apps/<slug>/installations/new
```

1. 选账号（个人 / 组织）→ **Install**。
2. **Repository access 选 `All repositories`** ✅
   —— 原型登录页那行加粗提示就是这个意思。
3. 点 Install 完成。

**为什么必须这一步**（`TECH_SPEC` §3.5.4）：

> **令牌可见范围 = 用户权限 ∩ App 权限 ∩ 安装时勾选的仓库**

只勾了部分仓库 ⇒ GitDuo 里**永远看不到**其余仓库（不是 403，是列表里压根没有）。
用户若选了 `Only select repositories`，必须在设置页把新仓库补进安装范围。

> 之后改安装范围：`https://github.com/settings/installations` → 找到 GitDuo → Configure。

---

## 5. 填进本地工程

编辑仓库根目录下的 **`Secrets.xcconfig`**（git-ignored；模板见 `Secrets.xcconfig.example`）：

```
GITDUO_CLIENT_ID = <粘贴 Client ID>
```

方案 A 还要加一行（并同步改 `project.yml` 注入 `Info.plist`，这步我来做）：

```
GITDUO_CLIENT_SECRET = <粘贴 Client secret>
```

然后重新生成工程并验证注入是否生效：

```bash
make gen && make build
/usr/libexec/PlistBuddy -c "Print :GitDuoClientID" \
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

---

## 7. 常见坑速查

| 现象 | 原因 | 处理 |
|---|---|---|
| `redirect_uri_mismatch` | 请求里的 `redirect_uri` 与注册值不完全一致 | 逐字符比对 §2.4；注意 URL 编码（`gitduo://oauth/callback` → `gitduo%3A%2F%2Foauth%2Fcallback`），且**不要带附加参数** |
| `incorrect_client_credentials` | `client_id` / `client_secret` 写错（如误用了 App ID） | 用设置页上的 **Client ID**，两者不同 |
| `bad_verification_code` | `code` 过期（**10 分钟**）或已用过 | 重新发起授权；`code` 一次性 |
| Star / 关注 **403** | 漏勾 `Starring` / `Followers` | §2.10 勾上；**改权限后已安装用户需重新批准** |
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
| 改 **App name** | slug 跟着变 ⇒ 安装链接失效 |
| 切 **Only on this account ↔ Any account** | 零成本，随时可切 |

---

## 9. 待你拍板：D4 —— secret 怎么处理（方案 A / B / C）

| 方案 | 做法 | 代价 | 与现有资产的关系 |
|---|---|---|---|
| **A**（推荐） | 内嵌 `client_secret` + PKCE | secret 可被反编译取出；GitHub 官方明确认可这是 public client 的做法 | **原型/文档的授权码流程完全不用改**，只改 8 处措辞（§0.1 表）+ `Secrets.xcconfig` 多一行 |
| **B** | 启用 Device Flow，不生成 secret | UX 退化（8 位 user_code + 手动输入）；**官方反对**；**原型登录页/授权页那一屏要重做** | 改动最大：§3.1 流程重写 + 原型重做 + harness 登录段断言重写 |
| **C** | 加一个极薄中继（如 Cloudflare Worker，免费）换令牌 | 违背 `TECH_SPEC` 决策「**无后端**」（决策 #5），需要维护一个域名与服务 | 文档决策表要改；工程侧反而更简单 |

**我的建议：A。** 理由：GitHub 自己的文档就是这么建议 public client 的；
本项目的"客户端不持 secret"前提**在 GitHub 上从来无法成立**（GitHub 不区分客户端类型）；
而 B 会让 §3.9 那套 `state` + PKCE 防护与原型整屏作废，C 则要推翻"零后端"这条已定决策。

> 拍板后我会一次性收口：改 `TECH_SPEC` §3.1 / §3.5 / §3.7 / §3.9 相关行 + `AGENTS.md` 铁律 9 +
> `PRD.md` §4.0.1 安全行 + 原型登录页 fnote + `AppConfig.swift` 注释 + `Secrets.xcconfig.example`，
> 并跑完整回归（原型 260 项断言）与 `make verify`。

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
