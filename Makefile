# GitDuo 2.0 —— 验证闭环的**唯一入口**
#
# 纪律：改完代码必须跑 `make verify`（= 三个包的单测 + 模拟器构建）。
# 不给 AI 一个可执行命令的改动，等于没有验证。

SHELL := /bin/bash
SCHEME := GitDuo
SIMULATOR_DESTINATION := generic/platform=iOS Simulator
# ⚠️ 新增 Package 必须登记在此，否则它不会进 `make test`（"漏跑"比"跑失败"更危险）
PACKAGES := GitHubAPI GitDuoAuth GitDuoCore GitDuoDesign

.PHONY: help gen test test-% build verify clean

help:
	@echo "make gen      xcodegen 生成 GitDuo.xcodeproj（改 project.yml / 增删文件后必跑）"
	@echo "make test     跑四个 Swift Package 的全部单测（Swift Testing）"
	@echo "make build    为 iOS 模拟器构建 App（无签名）"
	@echo "make verify   以上全跑（提交前必跑）"

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

clean:
	rm -rf GitDuo.xcodeproj build
	@for pkg in $(PACKAGES); do ( cd Packages/$$pkg && swift package clean ); done
