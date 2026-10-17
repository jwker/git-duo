# T1 计划 —— 给 App target 补测试 target

> 建档：2026-10-17 · 状态：**进行中（阶段 0–1 ✅ / 阶段 2 待办）**
> 来源：一次只读通读后的技术债清单（T1）。T1 的定义：**App 层（`GitDuo/`）目前零自动验证**。

---

## 0. 为什么做它

`GitDuo/` 是**最大**的一块（23,187 行、21 个 ViewModel、`Router`、`AppEnvironment`），
却**没有任何测试 target** —— 1782 个测试全在五个包里。后果：

- 改 App 层只能靠**人肉走查**（走查 85–89 全砸在这一格）；
- `make test` **根本不编译 App target** ⇒ "测试全绿"**推不出** App 是好的；
- `GitDuoKit/Package.swift` 与 `AGENTS.md` 都**明文承认**这一缺失，还被用来解释
  "领域层为什么单独成包" ⇒ 这是个**结构性**问题，不是遗漏。

---

## 1. 核实到的现状（每步都建在这上面）

| 事实 | 证据 | 对计划的意义 |
|---|---|---|
| `make test` **只遍历五个包** | `Makefile` L64–68 `for pkg in $(PACKAGES)` | 加了 App 测试后 `make test` **不会**跑到 ⇒ 必须新增 Make 规则 |
| `build` 用 `generic/platform=iOS Simulator` | `Makefile` L8 | **generic destination 不能跑测试** ⇒ 必须引入具体机型 |
| VM 是**构造注入** | `SearchViewModel.init(loader:store:)`，`store: any SearchHistoryStore`（协议） | ✅ 已有接缝，**不用为测试改 VM 签名** |
| 领域层已备桩替换点 | `LoadSearch.init(source: any SearchDataSource)`；`SearchDataSource`/`SearchHistoryStore` 均为协议（在 `GitDuoKit`） | ✅ fake 一注入即可 |
| **21 个 VM 零 `import SwiftUI`** | 逐文件 grep：0/21 | 决定 §6 岔路口 |
| 13 个 VM `import GitDuoDesign` 但**代码零引用** | 逐文件核对：代码引用数全 = 0（命中 4 处全在注释） | 残留 import，抽包时删 |
| VM **不引用 App 层类型** | grep `Route`/`AppEnvironment`/`AuthState`/`Router`：**0 处代码命中** | 同 §6 |
| 仅 3 个 VM `import UIKit`，用途只有 `UIPasteboard` | `FileViewModel`/`RepoCodeViewModel`（`RepoDetailViewModel` 连它都是残留） | §6 的唯一小障碍 |
| Debug 已开 `ENABLE_TESTABILITY = YES` | `GitDuo.xcodeproj/project.pbxproj` L894（Debug 配置段） | ✅ `@testable import` 的前提已满足 |
| **`iPhone 17 Pro` = iOS 26.5；`iPhone 18 Pro` = iOS 27.0** | `xcrun simctl list devices available` 分组 | ⚠️ **测试机型必须是 `iPhone 18 Pro`**（deployment target 27.0） |

### 硬约束（决定计划形态）

App target 是 `application` 而非 framework。要对它 `@testable import GitDuo`，
测试 bundle **必须挂宿主 App**（`TEST_HOST`）⇒ **每跑一次测试都会在模拟器里真的启动 GitDuo 本体**。
这是 Route A 与 Route B 的根本分野。

---

## 2. 目标与验收标准

**目标**：App 层能被 `make verify` 自动覆盖，不再只靠人肉走查。

**验收（四条，缺一不可）**：

- [ ] 1. `make verify` 输出里能看到 App 层测试用例在跑；
- [ ] 2. **故意改坏一处 VM 逻辑 ⇒ 测试变红**（证明它在测，不是摆设）；
- [ ] 3. `make test` 仍是**秒级**（不因 App 测试变慢）；
- [ ] 4. 架构铁律**不被破坏**（仍是五包 + App target）。

---

## 3. Route A —— 给 App target 补 test target（T1 的字面实现）

### 阶段 0 · 前置核实 ✅

- [x] `ENABLE_TESTABILITY`：Debug 已 = `YES`（pbxproj L894）
- [x] 固定 destination：**`platform=iOS Simulator,name=iPhone 18 Pro`**（iOS 27.0）
      ⚠️ 纠正：最初以为可用 `iPhone 17 Pro`，实测它是 **iOS 26.5**，与 deployment target 27.0 不符。
      ⚠️ 这是**新的环境契约**：换机 / CI 上必须有 iOS 27.0 的 `iPhone 18 Pro`。

### 阶段 1 · 加 test target（改 `project.yml`）—— ✅ 完成

**实测结果**：`xcodebuild test` **通过**（`** TEST SUCCEEDED **`）——
`Suite AppTestTargetSmokeTests` 2 个用例全过。整轮耗时 **~54 秒**，
其中**测试本身 0.003 秒**，其余全是构建 + 启动模拟器 + 启动 App 本体
（⇒ §5 代价 1 实测坐实）。

新建测试目标（**目录必须在仓库根**）：

```yaml
targets:
  GitDuoTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: GitDuoTests
    dependencies:
      - target: GitDuo        # xcodegen 据此自动设 TEST_HOST / BUNDLE_LOADER
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
```

挂进已有 scheme：

```yaml
schemes:
  GitDuo:
    test:
      config: Debug
      gatherCoverageData: false
      targets:
        - GitDuoTests          # 不写则 xcodebuild test 收不到
```

**坑**：测试目录**不能**叫 `GitDuo/Tests` —— App target 是 `sources: - path: GitDuo`，
放进去会被**编进 App 本体**。⇒ 用仓库根 `GitDuoTests/`。

改完 **必须 `make gen`**。

**✅ 实测确认（xcodegen 2.46.0）**：宿主与加载器是**自动接上**的，不需要手写 ——
生成物里 `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/GitDuo.app/GitDuo"`、
`BUNDLE_LOADER = "$(TEST_HOST)"`，且 `GitDuo` scheme 的 test 段已含 `GitDuoTests`。

**⚠️ 实测发现（阶段 1 踩到的真坑）—— 测试必须整块标 `@MainActor`**：

项目级 `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` 会让 App 层**每个类型连同它的一致性
（conformance）都变成 MainActor 隔离**。于是 `#expect(Route.profile == Route.profile)`
的 `==` 在**宏展开**（nonisolated 上下文）里直接编译失败：

    main actor-isolated conformance of 'Route' to 'Equatable'
    cannot be used in nonisolated context [#IsolatedConformances]

⇒ **App 层测试的默认姿势 = 整块 `@MainActor`**（阶段 2 那 21 个 VM 全是 `@MainActor`，同理）。
这一条是 §5 风险 4 的**具体兑现** —— 先前只是预判，现在是实测。

### 阶段 2 · 写第一个测试打样

选 `SearchViewModel`（纯逻辑 + 两个协议接缝 + 管的四件事最难靠点击发现：防抖 / 取消 / 缓存优先 / 分页）。

```swift
import Testing
@testable import GitDuo
import GitDuoKit

@Suite struct SearchViewModelTests { … }
```

⚠️ `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` 是**项目级**设置，自动作用到测试 target
⇒ 测试函数默认 MainActor 隔离，正好合适，不用额外标注。

### 阶段 3 · 接进 Makefile（不做这步 T1 等于没做）

```makefile
SIM_APP_DESTINATION ?= platform=iOS Simulator,name=iPhone 18 Pro

test-app: gen sandbox-fix
	xcodebuild -project GitDuo.xcodeproj -scheme $(SCHEME) \
		-destination '$(SIM_APP_DESTINATION)' -configuration Debug \
		-derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO \
		OTHER_SWIFT_FLAGS='$$(inherited) $(XCODE_SWIFT_FLAGS)' test

verify: test test-app build
```

- `sandbox-fix` **必须带**（测试也走 xcodebuild，同踩清单沙箱两坑）；
- `make test` **保持原样**（秒级），App 测试单独一条 ⇒ 满足验收 3；
- destination 用变量，换机时覆盖而不用改文件（照 `DEVICE_ID` 既有做法）。

### 阶段 4 · 分批扩面（滚动）

- 先测**纯逻辑、无 Design/UIKit 依赖**的 6 个：
  `SearchViewModel` · `RepoSectionViewModel` · `RepoListViewModel` · `MyStarsViewModel` ·
  `ExploreViewModel` · `ProfileViewModel`
- 再测需接缝的：`FileViewModel`（`UIPasteboard`）· `RepoDetailViewModel`
- **Views 暂不测**（非 T1 必要条件）

---

## 4. ⚠️ 必须同步的"文案契约"（不列就一定会漏）

`AGENTS.md §5` 与 `GitDuoKit/Package.swift` L9 都**明文写着**「App target 没有测试 target」，
且后者是**用来解释领域层为何单独成包**的论据。T1 落地后这句话**变成假的**。

- [ ] `AGENTS.md` §1「`make test` 不编译 App target」的警告 ⇒ 改写
- [ ] `AGENTS.md` §1 命令表 ⇒ 补 `make test-app`
- [ ] `Packages/GitDuoKit/Package.swift` 注释论据 ⇒ 更新
- [ ] `PagedListState.swift` / `LoadState.swift` 的"因为没有测试 target 才放这儿" ⇒ 更新（顺带触发 **T2**）
- [ ] `grep -rn "没有测试 target"` 全仓清点，逐个核实

---

## 5. 代价与风险

1. **`make verify` 会变慢** —— 每条 App 测试都要在模拟器里**启动一次 GitDuo 本体**（`TEST_HOST` 的必然结果）。
2. **新的环境依赖** —— 必须存在 iOS 27.0 的 `iPhone 18 Pro`，否则 `verify` 红。
3. **宿主测试更易 flaky** —— 时序 / MainActor / `@Observable` 通知时机的耦合面比纯包测试大。
4. **`@Observable` 断言有坑** —— 验证"属性变化触发"要在同一 actor，且不能依赖 registrar 内部细节。
5. **不会自动修好 T2 / T4**，但会让它们**首次变得可解**。

---

## 6. 岔路口：Route B（抽 ViewModel 成第六个包）

核实结果让它意外地便宜：21 个 VM 零 SwiftUI、不引用 App 层类型、13 个 Design import 全是残留、
UIKit 只用于 `UIPasteboard`。⇒ 把 21 个 VM 抽成 `GitDuoFeatureKit`，只留 Views 在 App。

| | Route A（App test target） | Route B（抽 VM 包） |
|---|---|---|
| 满足 T1 字面定义 | ✅ 是 | ⚠️ 变通 |
| 测试速度 | 慢（启模拟器 + 启 App） | ✅ 秒级 |
| 需要模拟器 | ✅ 必须 | ❌ 不需要 |
| 能覆盖 Views | ✅ 可以 | ❌ 不能 |
| 触碰架构铁律 | ❌ 不碰 | ⚠️ 要改（**需拍板**） |
| 顺带解决 T2 | 部分 | ✅ 较好 |

**建议**：先走 Route A（阶段 0–3，约 2 天）证明"App 层能被自动测"且**不动铁律**；
跑一段若模拟器成本不可接受，再评估 Route B。Route B 动的是保护最紧的那条铁律，值得单独一次决策。

---

## 7. 待拍板

1. **模拟器机型** —— 已按实测定为 `iPhone 18 Pro`（iOS 27.0）；可用 Make 变量覆盖。若要改，说一声。
2. **路线** —— 当前按建议先走 Route A。

---

## 8. 进度记录

- [x] 阶段 0 · 前置核实（发现 iPhone 17 Pro 是 iOS 26.5 ⇒ 改用 iPhone 18 Pro）
- [x] 阶段 1 · 加 test target（`project.yml` + `GitDuoTests/`）
      —— `xcodebuild test` 通过；`make verify` 通过（无回归）
- [ ] 阶段 2 · 第一个测试打样（`SearchViewModel`）
- [ ] 阶段 3 · 接进 Makefile（**验收 1 依赖它**）
- [ ] 阶段 4 · 分批扩面
- [ ] §4 文案契约同步
