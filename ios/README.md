# 行迹 · Xingji

iOS 17+ 原生行程与探店日记。SwiftUI + 高德地图/搜索 + Core Location + Core Data/CloudKit。

**当前交付是可继续构建的源码工程，尚未生成已签名的 iPhone 安装包，也未完成真机或 TestFlight 验收。** 本机只有 Command Line Tools，没有完整 Xcode/iOS SDK、开发者签名、高德 Key 或可验证的 CloudKit 容器。请勿把命令行逻辑测试通过等同于 iOS App 已构建通过。

## 已实现的源代码

- 地图、回顾、共享清单、设置四个原生页面；空数据状态不填充模拟记录。
- 日常低功耗到访识别；旅游连续定位、暂停/恢复、轨迹分段和断点说明。
- 自动匹配、待确认、更正店铺、手动补记、半星评分、文字、最多 12 张照片、忽略地点。
- SQLite 本地存储与 CloudKit 私人/共享数据库接入；离线继续本机保存。
- 独立探店清单副本、指定好友只读邀请、成员管理、主动更新分享版本、撤销/退出共享。
- 照片重新编码去除 EXIF/GPS、JSON/照片/分段 GPX 的 ZIP 导出、数据删除。
- 核心及持久化 XCTest 测试、无需 XCTest 的命令行验证程序。

第一版没有外卖读取入口、公开社区、广告、支付或独立账号系统。地图与真实共享必须先完成下面的服务配置。

## 在 iPhone 上运行

1. 安装并首次启动完整 Xcode，下载所需 iOS 平台，连接 iPhone。项目最低 iOS 17。可以对命令临时设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，不用修改全局开发目录。
2. 在项目目录用可用的现代 Ruby/Bundler 安装 SDK 依赖：

   ```sh
   bundle config set --local path vendor/bundle
   bundle install
   bundle exec pod install
   ```

   高德版本已固定：AMap3DMap 11.2.100、AMapSearch 9.8.1、AMapFoundation 1.9.1。首次 `pod install` 成功后保留生成的 `Podfile.lock`。Foundation 官方 podspec 排除了 arm64 模拟器；优先使用真实 iPhone，不要随意覆盖这个限制。

3. 复制配置模板并填写自己的值：

   ```sh
   cp Configuration/Local.xcconfig.example Configuration/Local.xcconfig
   ```

   - `XINGJI_BUNDLE_ID`：开发者账号中注册的 App 标识。
   - `DEVELOPMENT_TEAM`：Apple Developer Team ID。
   - `AMAP_API_KEY`：与上述 Bundle ID 对应的高德 **iOS SDK Key**，不是 Web API Key。
   - `XINGJI_CLOUD_CONTAINER`：同一开发团队创建的 CloudKit 容器。
   - `XINGJI_CLOUD_ENABLED = YES`：启用真实同步/共享。

   本地配置已加入 `.gitignore`。默认 Debug 配置只保存本机；缺 SDK/Key 时明确显示不可用，不假装定位或地图成功。不要将默认配置用于公开发布。

4. 打开 **Xingji.xcworkspace**（安装 Pods 后生成），选择 `Xingji` Scheme、你的团队和真实 iPhone。确认 iCloud/CloudKit、Push Notifications、Background Modes 中的 Location updates 和 Remote notifications 已启用。
5. 首次配置 CloudKit 时，在 Xcode Scheme 的 Run → Environment Variables 中临时添加 `XINGJI_INITIALIZE_SCHEMA=1`，运行 Debug App 并同意数据用途说明，创建开发环境 schema；完成后删除这个环境变量。生产环境部署见发布文档。
6. 运行后先确认用途说明；默认不会自动开启定位。开启日常记录后先授权使用期间定位，再通过设置中的“允许后台定位”申请始终允许。系统未给足权限时界面会标明受限。

未安装 Pods 的 `.xcodeproj` 可用于检视/构建本机功能的 Debug 路径，但没有真实地图/店铺搜索；Release 构建检查会阻止未配置服务的公开归档。

## 本机验证

```sh
./Scripts/check.sh
```

执行真实 Swift 编译和命令行行为检查、iOS 源码**语法解析**、工程/plist/资源引用检查。语法解析不是 iPhone 构建。

本次还利用 Command Line Tools 自带的 Catalyst SDK，以及从上述固定版本官方 SDK 下载的真实头文件，对全部 App 源码（含 SwiftUI/UIKit 和高德分支）做了补充类型检查。它不执行 iPhone 链接、签名或 SDK 运行。复现入口为 `Scripts/check_catalyst_types.sh`，高德头文件需位于忽略的 `.tools/vendor/` 目录；缺失时只检查无高德分支。

具备完整 Xcode 和签名后，运行 Scheme 的 `XingjiTests`。无 Pods 的 Debug 模拟器可验证本地路径；地图与高德必须按实际 SDK 支持的架构验证。

最近的本机检查输出见 `Docs/verification-output.txt`，真机待办见 `Docs/TESTING.md`。

## 代码组织

- `Sources/XingjiCore`：坐标、到访/旅行/共享快照、停留识别、匹配、去重、轨迹分段、GPX 与 ZIP。
- `Sources/XingjiData`：Core Data 模型、CloudKit 分享、照片编码。
- `App/Services`：iOS 生命周期、权限和定位、高德适配、应用数据协调。
- `App/Views`：四个页面与记录编辑、分享预览。
- `Verification`、`Tests`：可执行验证与 XCTest。
- `Docs/TESTING.md`：必须完成的真实设备/双账号测试。
- `Docs/RELEASE.md`：发布前配置和材料。

工程由 `Scripts/generate_project.py` 生成，已提交生成结果，打开工程不需要 XcodeGen。增删 App/Tests 的 Swift 文件后可重新运行脚本；它会覆盖 project.pbxproj，请先将自定义工程修改反映到脚本中。Swift Package 内新源码会自动发现。

## 关键行为

- 日常依赖系统到访通知，出现记录可能有延迟，不能承诺全天无遗漏。旅游同时监听系统到访，避免仅靠有距离门槛的 GPS 更新漏掉静止停留。
- 自动匹配仅用于精度较好且近距离内候选唯一的情况，仍标为“自动标记”；不等于验证真实消费。模糊结果保持待确认。
- 原始定位保留 WGS84，地图展示/搜索用高德转换成 GCJ-02，GPX 只输出 WGS84。
- 每段轨迹最多 256 点，15 秒检查一次持久化，切后台/暂停/结束时刷新。系统突然终止可能丢失最后尚未保存的少量点；恢复时明确分段。
- 共享图仅含清单、条目副本和照片副本，与私人对象没有 Core Data 关系。分享日期按中国时区显示日期字符串，无精确到访时刻。
- 原记录删除会撤回自己拥有的共享副本；删除旅行只删除轨迹，不删除到访记录。删除所有数据会先停止记录，再撤销/退出清单，最后删除私人数据；云端失败会显示错误，不报告全部删除成功。
- 撤销只能阻止后续授权读取，不能收回好友的截图或另存内容。数据同步也不是独立版本备份，误删除会传播。

目前没有耗电、发热、定位准确率、后台可靠性或云端权限的真机结论。正式发布前必须完成验收并补齐运营主体、隐私联系方式、服务许可与实际适用的上架材料。
