# DEVICE-TESTING —— GitDuo 2.0 真机测试

> **用途**：切片 1 的 **1.8 验收**（真授权 → 令牌落 Keychain → 杀进程重启仍登录），以及此后每片的真机复核。
> **为什么非得真机**：模拟器在 Keychain、entitlements、真实浏览器授权这几处会给出**假阳性**（见 §4）。
> 代码层面无解的步骤会用 🔒 标出 —— 那些只有你能做。

---

## 0. 一次性准备（只做一次）

| # | 做什么 | 在哪做 | 怎么算成功 |
|---|---|---|---|
| **1** | 🔒 **登录 Apple ID** | Xcode → Settings → Accounts → `+` → Apple ID | 账号出现在列表；其下能看到 Team |
| 2 | 打开**开发者模式** | 设备 → 设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启 → 输密码 | 设置首页出现「开发者」入口 |
| 3 | 信任本机 | USB 连 Mac，设备上点「信任此电脑」 | `xcrun devicectl list devices` 显示 `available (paired)` |
| 4 | 填 Team ID | `Secrets.xcconfig` 的 `GITDUO_DEVELOPMENT_TEAM` | 见下方取值方法 |

**第 1 步是整个流程里唯一无法用命令代替的**（需要密码，通常还有两步验证）。
本机状态（2026-10-06）：账号**已登录**，Team = `35FZY67FQU`（"weiku jiang (Personal Team)"，免费个人团队），
Xcode 已自动生成 `com.gitduo.app` 的 profile（有效期至 10-13 —— 免费账号 7 天）。
注意：钥匙串里另有一个**别的 Team**（`59T955ND9K`）的旧证书残留，**不要照它填**（见下）。

**第 4 步取值 —— 必须以「Xcode 登录账号的 Team」为准，不是钥匙串里那串：**

```bash
defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier
# → { "E76A6B0E-…" = ( { teamID = 35FZY67FQU; teamName = "… (Personal Team)"; } ); }
#                       ↑ 填这个
```

⚠️ **`security find-identity -v -p codesigning` 给出的 Team 可能与登录账号不同**（换过账号/换过机的常见残留）。
两者不一致时，`xcodebuild` 会拿着一个没人认领的 Team ID 去找账号，报**极具误导性的**
`No Accounts: Add a new account in Accounts settings` —— 让人误以为账号没登录（2026-10-06 实际踩到，
排查花了半天）。**判据：`No Accounts` 先查 Team 是否对得上，再怀疑账号。**

Team ID 和 client_id 一样属**本机个人配置**，所以放在 git-ignored 的 `Secrets.xcconfig`，
**不写进 `project.yml`**（别人 clone 后不会误用你的团队）。

---

## 1. 每次测试

```bash
make device                      # 构建（带签名）→ 安装 → 启动
```

**首次安装后设备会拒绝启动**（免费账号的证书不被信任），需要在设备上放行一次：

> 设备 → 设置 → 通用 → **VPN与设备管理** → 开发者 App → 信任 `Apple Development: …`

之后同一条 `make device` 就直接可用。分步执行的话：

```bash
make device          # 或以下三条分开跑
make install-device  # 只安装（已构建过时用）
make launch-device   # 只启动
```

换设备不用改文件（`DEVICE_ID` 可覆盖）：

```bash
DEVICE_ID=<新 UDID> make device
xcrun devicectl list devices       # 取 UDID
```

> ⚠️ **免费个人 Apple ID 的签名 7 天后过期**，届时 App 点不开（图标在但闪退）。
> 重新 `make device` 即可续期。本项目不需要任何特殊 entitlement（Keychain 走默认 access group），
> 所以**免费账号够用**，不必买开发者账号。

---

## 2. 切片 1 验收清单（1.8）

按顺序走，每步都要对：

| # | 操作 | 预期结果 | 验的是什么 |
|---|---|---|---|
| 1 | 冷启动（先杀掉 App） | 落**登录页**，无「凭据缺失」提示 | 门禁二分（1.7） |
| 2 | 点「使用 GitHub 登录」 | 弹出**系统**授权视图，域名是 `github.com` | `ASWebAuthenticationSession` |
| 3 | 看授权页的权限清单 | **6 条**，与登录页预告**一字不差** | P2 自查 · 权限数据单一来源（1.6） |
| 4 | 点 **Authorize** | **自动**跳回 GitDuo 并进入主界面（不需手动切回） | 回调 `gitduo://oauth/callback` · P3 自查 |
| 5 | 上滑**杀掉 App** → 重开 | **仍在主界面**，不要求重新登录 | 令牌落 Keychain（1.1）+ restore（1.4） |
| 6 | 我的 → **退出登录** | 回登录页，且提示「已退出登录 · 已同时撤销 GitHub 侧授权」 | 登出四步（1.5） |
| 7 | 打开 `github.com/settings/apps/authorizations` | **该 App 的授权已消失** | §3.6 的承诺**真的兑现了** |

> ⚠️ **第 6 步的入口位置（切片 1 期的临时约定）**：原型里登出走的是「我的 → 设置 → 退出登录」，
> 而**设置页属切片 9**。为让本切片验收能走完，暂时把「退出登录」直接放在**「我的」Tab 根页**；
> 切片 9 迁入设置页时**补齐二次确认弹层**（TECH_SPEC §3.6 要求，暂缺）。
| 8 | 开**飞行模式** → 冷启动 | 已登录状态**不应**被踢回登录页 | §3.2 第 3 条（断网 ≠ 登出） |
| 9 | 删 App → 重装 → 启动 | 观察：iOS **删除 App 不清 Keychain**，可能仍是登录态；若令牌已失效应自动清理 | §3.2 令牌有效性校验 |

**第 5 步和第 7 步是本切片的核心价值** —— 前者验"持久化是真的"，后者验"那句承诺不是谎话"
（项目有过先例：文案承诺撤销授权、实现却做不到）。

---

## 3. 常见错误对照

| 报错 | 真因 | 解法 |
|---|---|---|
| `Signing for "GitDuo" requires a development team` | 没配 Team | §0 第 4 步 |
| `No Accounts: Add a new account in Accounts settings` | ① **`GITDUO_DEVELOPMENT_TEAM` 与登录账号的 Team 不符**（更常见、更误导）② Xcode 没登录 Apple ID | 先对 Team（§0 第 4 步），再查账号（§0 第 1 步 🔒） |
| `Unable to install … ` / `Unable to launch … because the device was not … unlocked` | 设备锁屏（**构建与安装其实已成功**） | 解锁设备后重跑 `make launch-device` |
| `No profiles for 'com.gitduo.app' were found` | 账号没登录，或 Bundle ID 被他人占用 | 先做 §0 第 1 步；仍失败则改 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER` |
| `Unable to install … device is locked` | 设备锁屏 | 解锁设备 |
| `Untrusted Developer` / 图标点了闪退 | 未信任证书 | §1 的「VPN与设备管理」放行 |
| 设备不在 `devicectl list` 里 | 没连 / 没信任电脑 / 没开开发者模式 | §0 第 2、3 步 |
| 授权页没弹出来 | 设备无网络，或 App 的 scheme 未注册 | 检查网络；重装 App 让 `Info.plist` 生效 |
| `errSecMissingEntitlement (-34018)` 出现在日志 | 签名产物缺 `keychain-access-groups` | 自动签名正常会生成；确认用的是 Xcode 自动签名（`CODE_SIGN_STYLE=Automatic`） |

---

## 4. 只有真机能验的五件事（模拟器会给假阳性）

| # | 项 | 模拟器为什么不可信 |
|---|---|---|
| 1 | **Keychain 的 entitlement 链路** | 模拟器不强制 `keychain-access-groups`，`SecItemAdd` 必然成功；真机缺 entitlement 会 `-34018` |
| 2 | **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`** | 模拟器没有锁屏概念，「首次解锁后可访问」的语义只在真机成立 |
| 3 | **杀进程后的持久化** | 模拟器重置/重装的行为与真机不同；真机还能顺带观察"删 App 不清 Keychain" |
| 4 | **真实浏览器授权与回调** | 真机调起的是真实 Safari 会话、真实 GitHub 登录态、真实 `gitduo://` 跳回（模拟器的 `simctl openurl` 会先被**系统**确认框拦一道，App 侧处置验不到） |
| 5 | **签名 / 描述文件 / 证书信任** | 模拟器构建走 `CODE_SIGNING_ALLOWED=NO`，整条链路根本没被行使 |

> **实测记录（2026-10-06，iPhone 17 Pro）**：自动签名产出的 entitlements **只有三项** ——
> `application-identifier` · `com.apple.developer.team-identifier` · `get-task-allow`，
> **不含 `keychain-access-groups`**。按 iOS 规则，缺该 entitlement 时 Keychain 的默认 access group
> 回落到 `application-identifier`（`TEAMID.com.gitduo.app`）⇒ **实测可用**：
> 真实授权成功、令牌落 Keychain、**杀进程重启仍登录，日志中无 `errSecMissingEntitlement (-34018)`**。
> 故**不补**该 entitlement；若将来真出现 `-34018`，再显式加上。
>
> ```bash
> codesign -d --entitlements :- build/DerivedData-dev/Build/Products/Debug-iphoneos/GitDuo.app
> ```

---

## 5. 与 GitHub App 配置的关系

真机测试会真实走一遍授权，所以 `GITHUB-APP-SETUP.md` 里那两项自查（`REVIEW-CHECKLIST.md §3` 的 **P2 / P3**）
在**第 3、4 步**会被自然验证：

- **P2** → 第 3 步的权限清单是不是 6 条、与登录页预告一致
- **P3** → 第 4 步回调能否自动跳回 App

如果第 3 步权限对不上，说明 GitHub App 侧权限没勾齐（少勾 = 对应功能直接 403，且不会在本地暴露）。
