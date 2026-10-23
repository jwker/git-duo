# GitDuo 2.0 —— 验证闭环的**唯一入口**
#
# 纪律：改完代码必须跑 `make verify`（= 五个包的单测 + 模拟器构建）。
# 不给 AI 一个可执行命令的改动，等于没有验证。

SHELL := /bin/bash
SCHEME := GitDuo
SIMULATOR_DESTINATION := generic/platform=iOS Simulator
# ⚠️ 新增 Package 必须登记在此，否则它不会进 `make test`（"漏跑"比"跑失败"更危险）
PACKAGES := GitHubAPI GitDuoAuth GitDuoCore GitDuoDesign GitDuoKit

# ── 受限环境下的沙箱绕行（2026-10-06，AGENTS.md §2）──────────────────────────
# 某些受限运行环境（如被外层沙箱包裹的 shell）里，内核**拒绝一切嵌套 `sandbox-exec`**：
# `(allow default)` 能应用，`(deny default)` 一律 `Operation not permitted`。
# 而 SwiftPM 与 Xcode 都会用 `sandbox-exec` 包裹子进程，于是同时踩两处：
#
#   ① 包解析 —— SwiftPM 用沙箱编译 `Package.swift` 清单
#      ⇒ `xcodebuild: error: Could not resolve package dependencies: sandbox_apply…`
#   ② 宏展开 —— 编译器用沙箱拉起 `swift-plugin-server`
#      ⇒ `@Observable` / `@State` / `#Preview` 报 "produced malformed response"
#        （**极像源码写错，其实源码没错** —— 上一轮就是这么误判的）
#
# 两个坑的开关不同，且都**没有 per-invocation 的命令行形式**（试过的死路见 AGENTS.md §2）：
#   · `swift`  / `swiftc` 认 `--disable-sandbox` / `-disable-sandbox`
#   · Xcode 清单沙箱只认用户默认值 `IDEPackageSupportDisableManifestSandbox`
#
# 策略：**先探测**。本机沙箱正常 ⇒ 三个变量全为空，行为与从前一字不差；
#       探测失败 ⇒ 自动补开关（`SANDBOX_FIX=` 可跳过那次 `defaults write`）。
SANDBOX_BROKEN := $(shell /usr/bin/sandbox-exec -p '(version 1) (deny default)' /usr/bin/true >/dev/null 2>&1 || echo 1)
SANDBOX_FIX    ?= $(SANDBOX_BROKEN)
SWIFT_FLAGS       ?= $(if $(SANDBOX_BROKEN),--disable-sandbox,)
XCODE_SWIFT_FLAGS ?= $(if $(SANDBOX_BROKEN),-disable-sandbox,)

# 恢复 SwiftPM 自身沙箱：`make test SWIFT_FLAGS=` ；跳过偏好写入：`make build SANDBOX_FIX=`
sandbox-fix:
ifneq ($(SANDBOX_FIX),)
	@echo "⚠️  本机内核拒绝嵌套 sandbox-exec ⇒ 关闭 Xcode 清单沙箱（跳过：make … SANDBOX_FIX=）"
	@defaults write com.apple.dt.Xcode IDEPackageSupportDisableManifestSandbox -bool YES
	@echo "    撤销：defaults delete com.apple.dt.Xcode IDEPackageSupportDisableManifestSandbox"
endif

# ── 真机（切片 1 的 1.8 手测用；`make device` 需要先配 Secrets.xcconfig 的 TEAM）──
# 换设备：`xcrun devicectl list devices` 取 UDID，覆盖 DEVICE_ID 即可，不必改本文件。
DEVICE_ID ?= 00008150-001044A00EFB801C
DEVICE_APP := build/DerivedData-dev/Build/Products/Debug-iphoneos/GitDuo.app

# ⚠️ App 层测试的模拟器（2026-10-23 接进 `make verify`，T1 计划阶段 3）。
#    换机时覆盖这个变量即可，不必改文件（照 `DEVICE_ID` 的做法）。
#    ⚠️ 必须存在一台 **iOS 27.0** 的模拟器（部署目标是 27.0）—— 换机器时先看一眼
#    `xcrun simctl list devices available`。
SIM_APP_DESTINATION ?= platform=iOS Simulator,name=iPhone 18 Pro

.PHONY: help gen test test-% test-app build verify device install-device launch-device clean sandbox-fix

help:
	@echo "make gen      xcodegen 生成 GitDuo.xcodeproj（改 project.yml / 增删文件后必跑）"
	@echo "make test     跑五个 Swift Package 的全部单测（Swift Testing）"
	@echo "make test-<包名>  只跑某一个包（如 make test-GitDuoKit，名字照 PACKAGES 的拼写）"
	@echo "make test-app 跑 App 层单测（GitDuoTests，模拟器里跑）"
	@echo "make build    为 iOS 模拟器构建 App（无签名）"
	@echo "make verify   以上全跑（提交前必跑）"
	@echo "make device   真机全流程：构建(带签名) → 安装 → 启动（1.8 手测用）"
	@echo "make install-device / launch-device   只装 / 只启动（已构建过时用）"
	@echo "make sandbox-fix   受限环境下的沙箱绕行（build / device 已自动带上；正常机器上是空操作）"

# ── 生成工程 ────────────────────────────────────────────────────────────────
gen:
	xcodegen generate

# ── 单元测试（每个包独立，零 UI 依赖，秒级）────────────────────────────────
test:
	@for pkg in $(PACKAGES); do \
		echo "── swift test · $$pkg"; \
		( cd Packages/$$pkg && swift test $(SWIFT_FLAGS) ) || exit 1; \
	done

# 只跑一个包 —— `make test-GitDuoKit`（名字照 `PACKAGES` 里的拼写，**大小写敏感**）。
#
# ⚠️ 这条规则是 2026-10-07 补上的：此前 `.PHONY` 声明了 `test-%`、`help` 里也写了它，
#    但**规则本体一直不存在** ⇒ `make test-GitDuoKit` 直接报 "No rule to make target"。
#    声明与实现分家两天没人发现 —— 因为谁也没在切片中途只跑过一个包。
test-%:
	@test -d Packages/$* || { echo "⚠️  没有这个包：$*　可用的：$(PACKAGES)"; exit 1; }
	@echo "── swift test · $*"
	@( cd Packages/$* && swift test $(SWIFT_FLAGS) )

# ── 模拟器构建（不签名；CI 与本地同一条命令）───────────────────────────────
# `OTHER_SWIFT_FLAGS` 里带 `$(inherited)` 是有意的：不覆盖各包 Package.swift 的编译设置。
build: gen sandbox-fix
	xcodebuild -project GitDuo.xcodeproj \
		-scheme $(SCHEME) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-configuration Debug \
		-derivedDataPath build/DerivedData \
		CODE_SIGNING_ALLOWED=NO \
		OTHER_SWIFT_FLAGS='$$(inherited) $(XCODE_SWIFT_FLAGS)' \
		build

# ── App 层单测（GitDuoTests，2026-10-23 接进闭环 · T1 计划阶段 3）────────────
#
# ⚠️ 它与 `make test` **不是一回事**：那一条只跑五个 SwiftPM 包（秒级、零 UI 依赖），
#    这一条要**在模拟器里启动一次 GitDuo 本体**（`TEST_HOST` 的必然结果）⇒ 慢得多。
#    两条都进 `make verify` —— “漏跑”比“跑失败”更危险。
#
# ⚠️ `sandbox-fix` **必须带**（测试也走 xcodebuild，同踩清单沙箱两坑）。
test-app: gen sandbox-fix
	@echo "── xcodebuild test · App 层（GitDuoTests）"
	xcodebuild -project GitDuo.xcodeproj \
		-scheme $(SCHEME) \
		-destination '$(SIM_APP_DESTINATION)' \
		-configuration Debug \
		-derivedDataPath build/DerivedData \
		CODE_SIGNING_ALLOWED=NO \
		OTHER_SWIFT_FLAGS='$$(inherited) $(XCODE_SWIFT_FLAGS)' \
		test

# ── 验证闭环 ────────────────────────────────────────────────────────────────
verify: test test-app build
	@echo "✅ verify 通过：五个包单测 + App 层单测 + 模拟器构建"

# ── 真机（1.8 手测）──────────────────────────────────────────────────────────
# `-allowProvisioningUpdates` 是必须的：自动签名需要联网向开发者门户申请证书/描述文件，
# 否则报 "No profiles for 'com.gitduo.app' were found"。
# 构建不碰设备；install / launch 要求**设备已解锁**。
device: gen sandbox-fix
	xcodebuild -project GitDuo.xcodeproj \
		-scheme $(SCHEME) \
		-destination 'id=$(DEVICE_ID)' \
		-configuration Debug \
		-allowProvisioningUpdates \
		-derivedDataPath build/DerivedData-dev \
		OTHER_SWIFT_FLAGS='$$(inherited) $(XCODE_SWIFT_FLAGS)' \
		build
	$(MAKE) install-device
	@$(MAKE) launch-device 2>/dev/null || { \
		echo ""; \
		echo "⚠️  启动未成功。构建与安装均已成功，最常见的原因是**设备锁屏**。"; \
		echo "    解锁设备后重跑：make launch-device"; \
		echo "    若这是第一次安装，还需先在设备上信任证书："; \
		echo "      设置 → 通用 → VPN与设备管理 → 开发者 App → 信任"; \
	}

install-device:
	xcrun devicectl device install app --device $(DEVICE_ID) $(DEVICE_APP)

launch-device:
	xcrun devicectl device process launch --device $(DEVICE_ID) com.gitduo.app

clean:
	rm -rf GitDuo.xcodeproj build
	@for pkg in $(PACKAGES); do ( cd Packages/$$pkg && swift package clean ); done
