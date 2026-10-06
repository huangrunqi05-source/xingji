import SwiftUI
import CoreLocation
struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var deleteAll = false
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var showingExport = false
    @State private var error: String?
    var body: some View {
        List {
            Section("记录状态") {
                RecordingCard(tracker:model.tracker).listRowInsets(EdgeInsets())
                Button("允许后台定位") { model.tracker.requestAlways() }
                Button("打开系统权限设置") { if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Text("后台记录需要定位授权。低电量、关闭精确定位、强制结束 App 或系统资源限制，都可能造成记录缺口。").font(.caption).foregroundStyle(.secondary)
            }
            Section("数据保存") {
                Label(model.syncStatus,systemImage:"icloud")
                Button("检查 iCloud 状态") { Task { await model.refreshCloudStatus() } }
                Text("记录首先保存在本机。iCloud 暂不可用时，可以继续记录；同步与好友共享需要有效的 iCloud 账号。").font(.caption).foregroundStyle(.secondary)
            }
            Section("忽略的地点") {
                if model.ignored.isEmpty { Text("没有忽略的地点").foregroundStyle(.secondary) }
                ForEach(model.ignored) { place in HStack { VStack(alignment:.leading) { Text(place.name); Text("附近 \(Int(place.radius)) 米").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("恢复记录") { model.removeIgnored(place) } } }
            }
            Section("导出与删除") {
                Button {
                    exporting=true
                    Task { @MainActor in
                        do { exportURL=try model.export(); showingExport=true } catch { self.error=error.localizedDescription }
                        exporting=false
                    }
                } label: { Label(exporting ? "正在准备导出…" : "导出记录、照片和 GPX",systemImage:"square.and.arrow.up") }.disabled(exporting || model.isBusy)
                Text("导出 ZIP 包含私人数据，分享前请确认接收人。第一版暂不支持导入恢复。").font(.caption).foregroundStyle(.secondary)
                Button("删除所有数据",role:.destructive) { deleteAll=true }.disabled(model.isBusy)
                if model.isBusy { ProgressView("正在删除并撤销共享…") }
            }
            Section("关于行迹") {
                NavigationLink("数据与隐私说明") { PrivacyView() }
                LabeledContent("版本",value:"1.0 · 开发版")
                Text("记录你去过的地方，收藏值得再去的店。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("设置")
        .sheet(isPresented:$showingExport,onDismiss:cleanupExport) { if let exportURL { ActivitySheet(items:[exportURL],onComplete:{ showingExport=false }) } }
        .confirmationDialog("删除所有私人记录、照片和旅行路线，并撤销或退出共享清单？此操作无法撤销。",isPresented:$deleteAll,titleVisibility:.visible) { Button("删除所有数据",role:.destructive) { Task { await model.deleteAll() } } }
        .modifier(ErrorAlert(message:$error))
    }
    private func cleanupExport() { if let exportURL { try? FileManager.default.removeItem(at:exportURL) }; exportURL=nil }
}
struct PrivacyView: View {
    var body: some View {
        List {
            Section("位置") { Text("只有开启记录后才采集位置。日常模式保存停留地点和时间，旅游模式额外保存轨迹。关闭记录停止采集；你可单独删除记录或删除全部数据。") }
            Section("照片与评分") { Text("仅通过系统照片选择器读取你选中的照片，不扫描相册。导入图片会重新编码，移除定位元数据。评分和文字由你主动填写。") }
            Section("iCloud 与好友") { Text("记录在本机保存并通过配置的 iCloud 私人数据库同步。好友共享使用独立副本，内容由你确认；不共享完整路线、精确到访时刻或其他私人记录。撤销访问在云端处理后生效，无法收回对方已另行保存的内容。") }
            Section("第三方地图") { Text("高德提供地图、坐标转换和店铺搜索。查询附近店铺时会发送查询位置；查询关键词时会发送输入内容。地图服务的数据处理以高德隐私政策为准。"); Link("高德隐私政策",destination:URL(string:"https://developer.amap.com/pages/privacy/")!) }
            Section("管理数据") { Text("可在设置中导出记录、照片和 GPX 路线，或删除所有数据。删除已同步的数据需要等待 iCloud 同步完成。当前版本没有广告、第三方行为分析或外卖订单读取。") }
        }.navigationTitle("数据与隐私").navigationBarTitleDisplayMode(.inline)
    }
}
