# 发布前步骤

1. 使用自有 Apple Developer 团队、独立 Bundle ID、高德 iOS Key 与 CloudKit 容器；确认 Key 绑定正确。`Local.xcconfig` 不进入 Git。
2. 实际运行 `pod install`，检查 SDK 官方版本与平台架构、隐私清单、服务许可/配额；保留 Podfile.lock。当前按官方 podspec 固定版本，依赖尚未在本机通过 CocoaPods 集成和 iOS 链接验证。
3. Xcode 执行 iPhone Debug 构建、`XingjiTests`、Archive。Release 前置脚本拒绝示例 Bundle ID、空 Key、未启用 CloudKit、空团队或未安装 Pods；这不能替代人工发布验收。
4. 开发容器中初始化完整 CloudKit 模型。审核 record types、索引与分享关系；CloudKit Console 将 schema 部署到 Production，再进行 TestFlight。生产 schema 不能随意删字段；后续模型升级需保留兼容。
5. 依据真实业务与数据流补齐运营主体、联系方式、用户协议、对外可访问的隐私政策、App Store 隐私填写、定位用途说明，以及中国大陆上架实际适用的备案信息。仓库内用途说明和 privacy manifest 是技术起点，不是自动满足所有上架要求的证明。
6. 检查地图来源标识/审图号在各种屏幕和浮层下可见，核实高德许可及 POI 数据持久化使用范围，不能批量抓取地图或建立替代地图数据库。
7. 完成 TESTING.md 的定位/耗电、双账号、生产共享、删除/撤销、可访问性场景。外卖全自动同步未验证，不出现在上架文案中。
8. 使用真实设备截取 App Store 图片，审阅应用说明后提交审核。没有签名和真机验证时不交付 IPA 或声称已上架。

参考：
- [高德 iOS 接入](https://developer.amap.com/api/ios-sdk/gettingstarted)
- [高德许可与配额](https://developer.amap.com/upgrade)
- [Apple Core Data 共享示例](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users)
- [App Store 应用信息](https://developer.apple.com/cn/help/app-store-connect/reference/app-information/app-information/)
