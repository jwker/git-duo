# GitDuo 2.0 —— 验证闭环的**唯一入口**
#
# 纪律：改完代码必须跑 `make verify`（= 三个包的单测 + 模拟器构建）。
# 不给 AI 一个可执行命令的改动，等于没有验证。

SHELL := /bin/bash
SCHEME := GitDuo
SIMULATOR_DESTINATION := generic/platform=iOS Simulator
# ⚠️ 新增 Package 必须登记在此，否则它不会进 `make test`（"漏跑"比"跑失败"更危险）
PACKAGES := GitHubAPI GitDuoAuth GitDuoCore GitDuoDesign

# ── 真机（切片 1 的 1.8 手测用；`make device` 需要先配 Secrets.xcconfig 的 TEAM）──
# 换设备：`xcrun devicectl list devices` 取 UDID，覆盖 DEVICE_ID 即可，不必改本文件。
DEVICE_ID ?= 00008150-001044A00EFB801C
DEVICE_APP := build/DerivedData-dev/Build/Products/Debug-iphoneos/GitDuo.app

.PHONY: help gen test test-% build verify device install-device launch-device clean

help:
	@echo "make gen      xcodegen 生成 GitDuo.xcodeproj（改 project.yml / 增删文件后必跑）"
	@echo "make test     跑四个 Swift Package 的全部单测（Swift Testing）"
	@echo "make build    为 iOS 模拟器构建 App（无签名）"
	@echo "make verify   以上全跑（提交前必跑）"
	@echo "make device   真机全流程：构建(带签名) → 安装 → 启动（1.8 手测用）"
	@echo "make install-device / launch-device   只装 / 只启动（已构建过时用）"

# ── 生成工程 ────────────────────────────────────────────────────────────────
gen:
	xcodegen generate

# ── 单元测试（每个包独立，零 UI 依赖，秒级）────────────────────────────────
test:
	@for pkg in $(PACKAGES); do \
		echo "── swift test · $$pkg"; \
		( cd Packages/$$pkg && swift test ) || exit 1; \
	done

# ── 模拟器构建（不签名；CI 与本地同一条命令）───────────────────────────────
build: gen
	xcodebuild -project GitDuo.xcodeproj \
		-scheme $(SCHEME) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-configuration Debug \
		-derivedDataPath build/DerivedData \
		CODE_SIGNING_ALLOWED=NO \
		build

# ── 验证闭环 ────────────────────────────────────────────────────────────────
verify: test build
	@echo "✅ verify 通过：四个包单测 + 模拟器构建"

# ── 真机（1.8 手测）──────────────────────────────────────────────────────────
# `-allowProvisioningUpdates` 是必须的：自动签名需要联网向开发者门户申请证书/描述文件，
# 否则报 "No profiles for 'com.gitduo.app' were found"。
# 构建不碰设备；install / launch 要求**设备已解锁**。
device: gen
	xcodebuild -project GitDuo.xcodeproj \
		-scheme $(SCHEME) \
		-destination 'id=$(DEVICE_ID)' \
		-configuration Debug \
		-allowProvisioningUpdates \
		-derivedDataPath build/DerivedData-dev \
		build
	$(MAKE) install-device launch-device

install-device:
	xcrun devicectl device install app --device $(DEVICE_ID) $(DEVICE_APP)

launch-device:
	xcrun devicectl device process launch --device $(DEVICE_ID) com.gitduo.app

clean:
	rm -rf GitDuo.xcodeproj build
	@for pkg in $(PACKAGES); do ( cd Packages/$$pkg && swift package clean ); done
