# 原生控件改造计划

> 建档 2026-10-17。原计划文档 `NATIVE-MIGRATION.md` 已于 2026-10-17 从工作区删除，
> 要原文只能在 git 历史里取：`git show <删除前那次提交>:NATIVE-MIGRATION.md`。
> 视觉判定与口径在 `.ai/memory.md` §4「已定口径」；本文件只管**这活做到哪、还剩什么**。

## 口径

- 原型降级成「**功能清单**」，**视觉正本 = Apple HIG / SwiftUI 官方控件**。
- 计划里的分组：**A 44 项**有官方对应 · **B 32 项**官方有积木但拼不出原形状、重写 · **C 7 项永远自绘**
  （**别把这 7 件当成"还没改完"** —— 它们内部也已换用官方积木）。

## 进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 口径落地 | ✅ |
| P1 | 白拿系统行为（骨架 → `.redacted`，102 处自绘骨架全清） | ✅ |
| P2 | 按钮与控件样式 | ✅ |
| P3 | 列表主干（`List` 迁移边界由走查 **89/90** 定型：只迁朴素行列表，富详情页留 `ScrollView`） | ✅ |
| P4 | 弹层（`SheetPrimitives` 五件退休；`Repo/Views/Sheets/` 11 个 + `ExploreFilterSheet` 全走 `Form`） | ✅ |
| P5 | 令牌收尾 | ⬜ **未做 —— 下一步** |
| P6 | 自绘件内部改用官方积木 | ◐ 部分 |

## P5 的明细

`Theme.Palette` 48 色 → Asset Catalog / 语义色；`Spacing` / `Radius` / `Font` 瘦身；
补 `@ScaledMetric` + 动态类型。**判据：全仓 `@ScaledMetric` 现在 0 处。**
