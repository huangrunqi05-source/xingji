import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("privacyAccepted") private var consent = false
    var body: some View {
        Group {
            if let failure = model.storageFailure {
                ContentUnavailableView { Label("无法打开本机记录",systemImage:"externaldrive.badge.exclamationmark") } description: { Text("\(failure)\n请保留现有数据并重新打开 App，不会自动清空记录。") }
            } else if !consent { WelcomeView() }
            else {
                TabView {
                    NavigationStack { MapScreen() }.tabItem { Label("地图",systemImage:"map") }
                    NavigationStack { TimelineScreen() }.tabItem { Label("回顾",systemImage:"clock.arrow.circlepath") }
                    NavigationStack { ListsScreen() }.tabItem { Label("共享清单",systemImage:"person.2") }
                    NavigationStack { SettingsScreen() }.tabItem { Label("设置",systemImage:"slider.horizontal.3") }
                }
            }
        }.modifier(ErrorAlert(message:$model.error))
    }
}
struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:28) {
                Image(systemName:"point.topleft.down.to.point.bottomright.curvepath").font(.system(size:64,weight:.light)).foregroundStyle(Theme.green).padding(.top,56)
                VStack(alignment:.leading,spacing:12) {
                    Text("行迹").font(.system(size:42,weight:.bold,design:.rounded))
                    Text("把日子，留在地图上。").font(.title2).foregroundStyle(.secondary)
                }
                Label("日常记住停留，旅行留住沿途。",systemImage:"location.circle")
                Label("用照片和评分，收藏每一次体验。",systemImage:"photo.on.rectangle.angled")
                Label("选择想分享的记录，邀请好友查看。",systemImage:"person.2")
                VStack(alignment:.leading,spacing:12) {
                    Text("由你决定何时记录").font(.headline)
                    Text("默认关闭定位记录，开启后才申请定位权限。日常模式保存停留，旅游模式保存路线；你可以随时暂停、关闭或删除。")
                    Text("记录首先保存在本机；配置并启用 iCloud 后同步至你的私人空间。共享清单只包含你选中的记录副本。高德 SDK 提供地图与店铺查询，会按其隐私政策处理提供服务所需的信息。")
                    Link("阅读高德隐私政策",destination:URL(string:"https://developer.amap.com/pages/privacy/")!)
                }.font(.footnote).foregroundStyle(.secondary).padding(20).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:20))
                Button { model.activatePrivacyConsent() } label: { Text("同意并开始使用").font(.headline).frame(maxWidth:.infinity).padding(.vertical,12) }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("同意数据用途说明不会自动开启定位记录。 ").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.background(Theme.cream)
    }
}
struct RecordingCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var tracker: TrackingController
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Image(systemName:tracker.state.mode == .touring ? "point.topleft.down.to.point.bottomright.curvepath" : "leaf")
                Text(tracker.state.mode == .touring || tracker.state.mode == .paused ? "旅途中" : "我的日常").font(.headline)
                Spacer()
                Circle().fill(tracker.state.mode == .off || tracker.state.mode == .paused ? Color.secondary : Theme.green).frame(width:8,height:8)
            }
            Text(tracker.status).font(.caption).foregroundStyle(.secondary)
            HStack {
                switch tracker.state.mode {
                case .off:
                    Button("开启日常记录") { tracker.enableDaily() }.buttonStyle(.borderedProminent)
                    Button("开始旅游") { model.startTrip() }.buttonStyle(.bordered)
                case .daily:
                    Button("开始旅游") { model.startTrip() }.buttonStyle(.borderedProminent)
                    Button("关闭记录") { model.finishTrip(turnOff:true) }.buttonStyle(.bordered)
                case .touring:
                    Button("暂停") { tracker.pause() }.buttonStyle(.bordered)
                    Button("结束旅行") { model.finishTrip() }.buttonStyle(.borderedProminent)
                case .paused:
                    Button("继续旅行") { tracker.resume() }.buttonStyle(.borderedProminent)
                    Button("结束旅行") { model.finishTrip() }.buttonStyle(.bordered)
                }
            }.font(.subheadline.weight(.semibold))
        }.padding(18).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22)).shadow(color:.black.opacity(0.05),radius:12,y:5)
    }
}
