<img src="GitDuo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" alt="GitDuo 图标">

# GitDuo

一个 iPhone 上的 GitHub 客户端。

## 环境要求

- Xcode 27 及以上（iOS 27 SDK）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)，`brew install xcodegen`

## 跑起来

```bash
cp Secrets.xcconfig.example Secrets.xcconfig   # 填入自己的 client_id 与 client_secret
make gen                                        # 生成 GitDuo.xcodeproj
make verify                                     # 跑单测 + 构建模拟器版
```

常用命令：

| 命令 | 作用 |
| --- | --- |
| `make gen` | 重新生成 Xcode 工程，改 `project.yml` 或增删文件后要跑 |
| `make test` | 跑五个包的单测 |
| `make build` | 构建模拟器版 |
| `make verify` | 上面三件事一起跑 |
| `make device` | 构建真机版、安装并启动（需要先在 `Secrets.xcconfig` 里配好开发团队 ID） |

## 关于登录

用 GitHub App 的 OAuth 流程登录，凭据存在 Keychain 里，不写日志、不进 UserDefaults。想自己部署的话，需要在 GitHub 上注册一个 App，回调地址填 `gitduo://oauth/callback`，权限勾 Contents、Issues、Pull requests、Metadata、Starring、Followers。

## 代码结构

五个 SwiftPM 包加一个 App target：

```
Packages/GitHubAPI     网络请求、OAuth 客户端、DTO、缓存
Packages/GitDuoCore    本地基础设施：Keychain、图片处理
Packages/GitDuoAuth    认证流程编排
Packages/GitDuoDesign  设计令牌与通用组件
Packages/GitDuoKit     领域层，只描述「是什么」，不碰 UI
GitDuo                 组合根与页面
```

依赖方向是表现层 → 领域层 → 数据层。`AGENTS.md` 里有更细的约束和命令说明，动手改代码前建议先看那个。
