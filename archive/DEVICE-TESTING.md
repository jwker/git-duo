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
| 8 | 开**飞行模式** → 冷启动 | 已登录状态**不应**被踢回登录页 | §3.2 第 3 条（断网 ≠ 登出） |
| 9 | 删 App → 重装 → 启动 | 观察：iOS **删除 App 不清 Keychain**，可能仍是登录态；若令牌已失效应自动清理 | §3.2 令牌有效性校验 |
| 10 | 登出后从 Mac 拉设备上的 `Cache.db` 查（见下） | **一条请求记录都不剩** | 登出清接口缓存（§3.6 ③） |

**第 5 步和第 7 步是本切片的核心价值** —— 前者验"持久化是真的"，后者验"那句承诺不是谎话"
（项目有过先例：文案承诺撤销授权、实现却做不到）。

> ⚠️ **第 6 步的入口位置（切片 1 期的临时约定）**：原型里登出走的是「我的 → 设置 → 退出登录」，
> 而**设置页属切片 9**。为让本切片验收能走完，暂时把「退出登录」直接放在**「我的」Tab 根页**；
> 切片 9 迁入设置页时**补齐二次确认弹层**（TECH_SPEC §3.6 要求，暂缺）。

### 第 10 步怎么做（缓存必须为空）

```bash
DEV=00008150-001044A00EFB801C; BID=com.gitduo.app
xcrun devicectl device copy from --device $DEV --domain-type appDataContainer \
  --domain-identifier $BID --source Library/Caches/$BID/Cache.db --destination /tmp/Cache.db
# ⚠️ 若库是 WAL 模式，把 -wal / -shm 一并取回，否则读到的是旧视图
sqlite3 /tmp/Cache.db "select count(*) from cfurl_cache_response;"
# 期望 0（决策 #32 之后：API 会话不挂 URLCache，**任何时刻**都该是 0，不只是登出后）
# >0 ⇒ 要么登出没清干净，要么有人又把某个请求放回了带缓存的会话上

# ★ 第二道、更直接：直接搜令牌前缀（只看计数，不打印内容）
for f in Cache.db Cache.db-wal; do
  strings /tmp/$f | grep -c 'ghu_\|ghr_' | sed "s/^/$f: /"
done
# 期望 0 / 0。⚠️ URLCache 落盘的不只是响应体 —— request_object / proto_props 里会躺着
# 整个 Authorization 头（2026-10-06 实测命中过 2 次），所以"响应体没凭据"不等于"这库干净"
```

⚠️ **为什么这条要单独验**：真机实测（2026-10-06）发现换令牌的响应**曾被系统写进这个库**
（`access_token` / `refresh_token` 明文），而它**不受 Keychain 的 `AfterFirstUnlockThisDeviceOnly` 保护**；
更关键的是 —— **改掉写入路径并不会清除已经写下的副本**，只有登出时的显式清理才会
（`AuthCoordinator.signOut` → `HTTPCachePurging`）。
**同一天的第二次实测又发现**：`URLCache` 连**序列化请求对象**一起落盘 ⇒ `GET /user` 这种
"响应全是公开资料"的请求，也把 `Authorization: Bearer ghu_…` 写进了库（决策 #32）。

### 第 10 步的判据（容易读错，单独立一条）

实测（2026-10-06）：登出后 `cfurl_cache_response` / `cfurl_cache_receiver_data` **双双 0 行** ——
那份 13:23 落盘、含 `access_token` + `refresh_token` + `ghu_` 的副本**确实被清掉了**。
判读时有三个坑，踩一个就会得出相反结论：

1. **同一个 URL 是"替换"不是"新增"** ⇒ 别用"条目有没有变多"判"有没有写入"。
   要判写入路径是否还活着，看的是**旧条目的时间戳有没有被刷新**。
2. **重装 App 不会清容器**（实测：`Library/Cookies/Cookies.binarycookies` 与
   `SplashBoard/Snapshots` 的 mtime 跨两次重装**没变**）⇒ 缓存空掉**不能**归因于"刚重装过"。
   反过来同样要记住：**"缓存空了"本身不构成证据**，必须先在登出**之前**取一次基线
   （本项目基线 = 13:23 那两条）。
3. **WAL 模式**：只拉 `Cache.db` 会读到旧视图，`-wal` / `-shm` 必须一起拉。
   若 `pragma wal_checkpoint(FULL)` 返回 `log=0`，说明该 WAL 里**没有有效帧**，别拿它当"没数据"的证据。
4. **先看列的类型，再谈"变了没有"**（我自己踩过）：`cfurl_cache_response.time_stamp` 是
   **TEXT、UTC**（`2026-10-06 07:29:42`），**不是 CF 绝对时间**。
   我当时按 `datetime(time_stamp + 978307200, 'unixepoch', 'localtime')` 读 —— SQLite 把文本强转成
   数字 `2026` 再加偏移，**新旧记录都渲染成同一个 `2001-01-01 08:33:46`**，
   于是得出"时间戳一个字没变"的错结论（实则读法坏了）。**直接 `select time_stamp` 读原列。**

**当前进度（2026-10-06，iPhone 17 Pro）：10 步全过 → 切片 1 验收完成 ✅**

- ✅ **第 1 步**已实拍：登出态杀进程冷启动 ⇒ 登录页（无「凭据缺失」提示）
- ✅ **第 2 步**：真实系统授权视图弹出，域名 `github.com`
- ✅ **第 3 步**（**P2 自查**）：用户在 `github.com/settings/apps` 目视确认权限 = **6 条**，
  与登录页预告一致（Contents / Issues / Pull requests / Metadata / Starring / Followers）
- ✅ **第 4 步**：授权后自动跳回 App 进主界面（同时反证 **P3**：回调 `gitduo://oauth/callback` 可用）
- ✅ **第 5 步**（**本切片核心价值之一**）：杀进程重启仍登录
- ✅ **第 6 步**：退出登录 ⇒ 回登录页（用户确认）
- ✅ **第 7 步**（**另一项核心价值**）：`settings/apps/authorizations` 上该 App 授权**真的消失**（用户目视确认）
- ✅ **第 8 步**已实拍：**飞行模式下杀进程冷启动 ⇒ 仍在主界面 `@jwker`**（断网 ≠ 登出，§3.2）
- ◐ **第 9 步**已有观察：**Keychain 跨 App 重装保留**（重装后仍是登录态）；删 App 那一步未单独做
- ✅ **第 10 步**：见下方"第 10 步的判据"

**第 10 步的复验（决策 #32 之后，2026-10-06 15:45）** —— 证据比首次更干净：

用户走「退出登录 → 再登录一次」后，拉设备**原始**（未做本机 checkpoint）库实测：

| 检查项 | 结果 |
|---|---|
| `Cache.db` 主文件 | **4096 字节**（空库大小） |
| `cfurl_cache_response` / `_receiver_data` / `_blob_data` | **三表全 0 行** |
| `strings Cache.db Cache.db-wal` 搜 `access_token` / `refresh_token` / `ghu_` / `Bearer` | **全 0** |
| 同上搜 `github.com` / `api.github.com` | **全 0** —— 连一个 URL 都没有 |
| `fsCachedData/`（URL 缓存的大 body 落点目录） | **已不在容器清单里** |

**为什么这一轮证据更强**（关键判据，值得记住）：

- 修复前（15:29 那次登录）库里有**且仅有** `api.github.com/user` 一条。
- 15:42 我跑过 `make device` 重装 —— 但**升级安装不清容器**（第 130 行那条实测），
  所以那条记录在 15:42 之后**理应还在**。
- 15:45 用户登出 → 再登录。现在它**不在了**，而修复后版本（`noCache()`）不会再写任何条目
  ⇒ 它**只能是被登出清理删掉的**。这比首次"清空"的判读更硬：
  首次那个"空"还夹着"重装可能清容器"的混淆项，这次没有。

旁证两条：`httpstorages.sqlite-shm/wal` mtime 停在 **15:29**（`noCache()` 不挂 Cookie 罐，
这次登录连它都没碰）；`Library/Cookies/Cookies.binarycookies` mtime 仍是 **13:23**（无 Cookie 罐生效）。

⚠️ **`Cache.db` 恒为 0 是预期常态**（决策 #32：本包所有出网会话不挂 `URLCache`），
不再只是"登出后该为 0"。将来切片 2 要上 ETag 缓存时，落点必须是**自建存储**，不能回头启用系统缓存。

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
