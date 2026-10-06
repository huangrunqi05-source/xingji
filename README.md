# 行迹 Xingji

一个面向 iPhone 和桌面浏览器的私人探店本。记录去过的店、到访时间、半星评分、感受和照片。

**[打开网页版](https://huangrunqi05-source.github.io/xingji/)** · [使用说明](USAGE.md) · [开发与部署](DEVELOPMENT.md)

## 普通用户如何使用

1. 打开上面的网页版，无需注册或登录。
2. 点击「记一笔」，填写店铺和分店地址，可主动获取当前位置。
3. 保存到访时间，添加评分、文字和照片。
4. iPhone 用 Safari 打开后，通过分享菜单「添加到主屏幕」。

记录和照片保存在**当前设备、当前浏览器**的 IndexedDB 中，不上传 GitHub，也不会自动同步到其他设备。清理网站数据、无痕浏览或浏览器自动清理空间可能导致记录丢失，请定期导出。

## 功能与边界

- 手动到访记录、可选即时定位、修改时间、半星评分、每次最多 6 张照片。
- 按店名、日期、分类和评分筛选；同一分店汇总历史、再次到访。
- 照片在本机压缩并重新编码，移除原始定位元数据。
- 精选清单保存独立副本，分享前预览；可导出含照片的 HTML 文件发给朋友。文件不含坐标、精确时间或完整到访历史，已发送文件不能撤回。
- 导出全部记录及照片为 JSON；当前不支持备份文件导入。
- 首次联网缓存成功后可离线使用；定位及外部地图依赖设备和网络能力。
- 不支持后台自动行程记录、外卖订单同步、在线好友邀请，也没有内嵌地图。通过高德官方链接查看店铺。

## 仓库目录

| 目录 | 内容 | 当前用途 |
|---|---|---|
| `docs/` | 无依赖静态网页与离线缓存 | GitHub Pages 对外使用版 |
| `ios/` | SwiftUI / Core Data / CloudKit 工程 | 原生 iPhone 开发版，尚无可安装发行包 |
| `web-cloud/` | Swift 之外的 React / Vinext 云端实现 | 自行部署参考，依赖 Sites 身份层与 D1/R2 |
| `tests/` | 网页核心数据规则测试 | `npm test` |

这是三个不同运行版本。GitHub Pages 不会执行 `web-cloud/` 的服务器接口，也不会把其他版本的已有记录自动迁移到本机版。

## 本地运行

```sh
git clone https://github.com/huangrunqi05-source/xingji.git
cd xingji
python3 -m http.server 8080 --bind 127.0.0.1 --directory docs
```

在浏览器打开 `http://127.0.0.1:8080`。请通过 HTTP/HTTPS 访问，不要直接双击 HTML 文件。

测试不需要安装依赖：

```sh
npm test
npm run check
```

## 许可

本项目自有代码采用 [MIT](LICENSE) 许可。第三方依赖、地图 SDK 和照片保留各自许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
