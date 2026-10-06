# 开发与部署

## GitHub Pages

`docs/` 是可直接托管的完整静态站点，无后端、无 Key、无安装步骤。

1. Fork 或复制本仓库。
2. 在仓库 Settings → Pages 中选择 **Deploy from a branch**。
3. 分支选择 `main`，目录选择 `/docs`，保存。
4. 等待 GitHub 的 Pages 构建成功，使用设置页返回的 URL。

所有站内资源、manifest 和 Service Worker 均为相对路径，支持仓库子路径。Fork 后可修改 README 和页面里的源码链接；不会影响记录功能。更新离线文件清单或缓存策略时递增 `docs/sw.js` 的版本。现有打开的页面关闭后，新 Service Worker 才会激活。

## 数据结构

浏览器数据库 `xingji-local-v1`，包含 `visits` 与 `lists` 两个对象仓库。到访使用随机 UUID，分店使用独立 `placeKey`。照片经 Canvas 重新编码后作为 JPEG data URL 随记录保存在 IndexedDB。写入事务完成才显示成功，配额不足时保留表单供重试。

分享只通过用户点击导出触发；HTML 对文本进行转义，仅接受 JPEG data URL，不嵌入脚本。清单保存独立副本，不持有私人到访记录的引用。

## 云端实现

`web-cloud/` 保存现有云端版本源码，凭据和部署项目 ID 已移除。需要 Node 22.13+、Sites 部署环境以及逻辑绑定 `DB`、`BUCKET`。身份通过可信部署网关注入的认证头传入，不能直接暴露在允许访客伪造这些头的通用服务器上。

不要把 `web-cloud/` 当作 GitHub Pages 网站，也不要认为执行 `npm run build` 就完成身份验证配置。迁移到其他托管平台时必须先实现可信身份认证与服务端权限校验。

## iOS

见 `ios/README.md`。需要完整 Xcode、Apple Developer 签名、CloudKit 容器、高德应用 Key。仓库不含签名证书、个人配置或编译缓存；没有承诺可直接下载安装的 IPA。

## 验证

- `npm test`：评分、时间、隐私快照和安全导出。
- `npm run check`：浏览器脚本语法。
- 使用本地 HTTP 服务实测新增记录、刷新恢复、照片处理、清单导出、离线访问与 390px 手机布局。
