# 本机验证记录 · 2026-10-06

## 已通过

- Swift 6.1.2 命令行实际编译 XingjiCore、XingjiData 和 XingjiVerify。
- `Scripts/check.sh`：45 项行为检查通过，包括真实 SQLite 重开、ImageIO 照片 GPS/原始拍摄时间清除、系统 unzip 和 Python zipfile 校验。
- App Swift 文件语法解析、Xcode 工程/plist 格式、所有工程引用、资源和共享 Scheme 检查通过。
- 使用 Command Line Tools 中的 Catalyst SDK（target `arm64-apple-ios17.0-macabi`）完成整个 App 的补充类型检查。
- 高德类型检查使用从官方 11.2.100 / 9.8.1 / 1.9.1 SDK 下载的真实头文件，包含有高德依赖的代码分支。最终退出码 0，无警告。

检查记录见 `verification-output.txt`。补充类型检查脚本为 `Scripts/check_catalyst_types.sh`；下载的依赖头文件仅放在 `.tools/vendor/`，未作为应用资源或第三方二进制发布。

## 尚未完成

- 本机没有完整 Xcode 和 iPhoneOS SDK，未进行 iOS 设备目标的最终构建/链接、代码签名、安装或运行，也没有运行 XCTest。
- 尚未执行 CocoaPods 集成安装，因此未生成 Podfile.lock 和含 Pods 的 workspace。
- 没有可用的开发者团队、高德 iOS Key 和 CloudKit 容器配置，没有调用真实地图、店铺查询、iCloud 同步或共享服务进行端到端验收。
- 没有真机定位、耗电、发热、视觉布局、VoiceOver、双账号权限/撤销或 TestFlight 生产环境结果。
- 没有生成 IPA、提交审核或发布 App。

Catalyst 类型检查仅用于尽早发现代码/API 错误，不能代替 iPhone 构建与真机验收。后续按 `TESTING.md`、`RELEASE.md` 执行。
