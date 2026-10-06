import SwiftUI
import CoreData
import CloudKit
import XingjiCore
import XingjiData

struct ListsScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var creating = false
    @State private var title = ""
    var body: some View {
        List {
            Section {
                Text("和朋友交换值得再去的地方。").font(.title3.weight(.medium))
                Text("只有你选择加入的记录会被分享。清单成员仅可查看，私人地图和路线不会进入清单。").font(.subheadline).foregroundStyle(.secondary)
            }
            if model.lists.isEmpty { ContentUnavailableView("创建第一份探店清单",systemImage:"person.2.crop.square.stack",description:Text("例如「周末咖啡地图」或「值得再吃一次」。")) }
            ForEach(model.lists,id:\.objectID) { list in
                NavigationLink { ListDetailScreen(list:list) } label: {
                    VStack(alignment:.leading,spacing:6) {
                        Text(list.value(forKey:"title") as? String ?? "探店清单").font(.headline)
                        Text(model.store?.isOwner(list) == true ? "我创建的 · \(model.store?.entries(in:list).count ?? 0) 条记录" : "好友分享 · 只读").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,6)
                }
            }
        }.navigationTitle("共享清单")
        .toolbar { Button { creating=true } label: { Image(systemName:"plus") }.accessibilityLabel("新建共享清单") }
        .alert("新建清单",isPresented:$creating) {
            TextField("清单名称",text:$title)
            Button("取消",role:.cancel) {}
            Button("创建") { model.perform { _ = try model.requireStore().createList(title:title); title="" } }
        }
    }
}
struct ListDetailScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let list: NSManagedObject
    @State private var picking = false
    @State private var share: CKShare?
    @State private var shareVisible = false
    @State private var loading = false
    @State private var deleting = false
    @State private var selectedVisit: Visit?
    @State private var pendingSelection: Visit?
    private var owner: Bool { model.store?.isOwner(list) == true }
    private var entries: [NSManagedObject] { model.store?.entries(in:list) ?? [] }
    var body: some View {
        List {
            if owner {
                Section {
                    Button { picking=true } label: { Label("添加探店记录",systemImage:"plus.circle") }
                    Button {
                        loading=true
                        Task {
                            do { share=try await model.requireStore().prepareShare(list); shareVisible=true }
                            catch { model.error=error.localizedDescription }
                            loading=false
                        }
                    } label: { Label(loading ? "正在准备邀请…" : "邀请好友／管理成员",systemImage:"person.badge.plus") }.disabled(loading || Configuration.cloudIdentifier == nil)
                    if Configuration.cloudIdentifier == nil { Text("此清单已保存在本机。完成 iCloud 配置后才能邀请好友。").font(.caption).foregroundStyle(.secondary) }
                }
            } else { Text("好友共享的只读清单").foregroundStyle(.secondary) }
            if entries.isEmpty { ContentUnavailableView("清单还是空的",systemImage:"list.bullet.rectangle",description:Text(owner ? "从已有到访记录中挑选，并预览分享内容。" : "好友添加记录后，会同步到这里。")) }
            ForEach(entries,id:\.objectID) { entry in
                if let snapshot = try? model.store?.snapshot(entry) {
                    Section {
                        Text(snapshot.title).font(.title3.bold())
                        Text(snapshot.address).font(.caption).foregroundStyle(.secondary)
                        HStack { Text(snapshot.day); Spacer(); if let rating = snapshot.rating { Label(String(format:"%.1f",rating),systemImage:"star.fill").foregroundStyle(Theme.orange) } }.font(.subheadline)
                        if !snapshot.note.isEmpty { Text(snapshot.note) }
                        let photos = model.store?.sharedPhotos(entry) ?? []
                        if !photos.isEmpty { ScrollView(.horizontal) { HStack { ForEach(Array(photos.enumerated()),id:\.offset) { _,data in PhotoThumbnail(data:data) } } } }
                        if owner {
                            HStack {
                                if let visit = model.visits.first(where:{$0.id == snapshot.sourceVisitID}) { Button("从私人记录更新") { selectedVisit=visit } }
                                Spacer()
                                Button("移除",role:.destructive) { model.perform { try model.requireStore().removeEntry(entry) } }
                            }.font(.subheadline)
                        }
                    }
                }
            }
            Section { Button(owner ? "删除清单并停止共享" : "退出共享清单",role:.destructive) { deleting=true } }
        }
        .navigationTitle(list.value(forKey:"title") as? String ?? "探店清单").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$picking,onDismiss:{ selectedVisit=pendingSelection; pendingSelection=nil }) {
            NavigationStack {
                List(model.visits.filter { $0.place != nil }) { visit in Button { pendingSelection=visit; picking=false } label: { VisitRow(visit:visit) } }
                    .navigationTitle("选择探店记录").toolbar { Button("取消") { picking=false } }
            }
        }
        .sheet(item:$selectedVisit) { visit in NavigationStack { PublishSheet(visit:visit,fixedList:list) }.environmentObject(model) }
        .sheet(isPresented:$shareVisible,onDismiss:{model.reload()}) {
            if let share, let id = Configuration.cloudIdentifier { CloudShareController(share:share,container:CKContainer(identifier:id),store:model.store,list:list,onError:{model.error=$0}) }
        }
        .confirmationDialog(owner ? "删除清单并撤销所有成员的访问？" : "退出后将无法查看这份清单。",isPresented:$deleting,titleVisibility:.visible) {
            Button(owner ? "删除清单" : "退出清单",role:.destructive) {
                Task { do { try await model.requireStore().leaveOrDeleteList(list); model.reload(); dismiss() } catch { model.error=error.localizedDescription } }
            }
        }
    }
}
struct PublishSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    var fixedList: NSManagedObject?
    @State private var selectedID: NSManagedObjectID?
    @State private var sending = false
    @State private var error: String?
    private var ownedLists: [NSManagedObject] { model.lists.filter { model.store?.isOwner($0) == true } }
    private var target: NSManagedObject? { fixedList ?? ownedLists.first { $0.objectID == selectedID } }
    var body: some View {
        List {
            Section("分享预览") {
                Text(visit.title).font(.title2.bold())
                Text(visit.place?.address ?? "").foregroundStyle(.secondary)
                Text(visit.arrival.formatted(date:.abbreviated,time:.omitted))
                if let rating = visit.rating { Label(String(format:"%.1f",rating),systemImage:"star.fill").foregroundStyle(Theme.orange) }
                if !visit.note.isEmpty { Text(visit.note) }
                ScrollView(.horizontal) { HStack { ForEach(visit.photoIDs,id:\.self) { id in PhotoThumbnail(data:try? model.store?.photo(id)) } } }
            }
            Section {
                Text("好友会看到以上内容，不包含到达／离开时刻、路线或私人历史。照片会移除定位元数据。以后修改私人记录不会自动更新这份副本。").font(.footnote).foregroundStyle(.secondary)
                if let fixedList { LabeledContent("加入清单",value:fixedList.value(forKey:"title") as? String ?? "") }
                else {
                    Picker("加入清单",selection:$selectedID) {
                        Text("请选择").tag(NSManagedObjectID?.none)
                        ForEach(ownedLists,id:\.objectID) { list in Text(list.value(forKey:"title") as? String ?? "清单").tag(Optional(list.objectID)) }
                    }
                    if ownedLists.isEmpty { Text("请先在「共享清单」中新建一份清单。").foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("确认分享内容").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() }.disabled(sending) }
            ToolbarItem(placement:.confirmationAction) {
                Button(sending ? "保存中…" : "确认加入") { publish() }.disabled(target == nil || sending)
            }
        }.interactiveDismissDisabled(sending).modifier(ErrorAlert(message:$error))
    }
    private func publish() {
        guard let target else { return }; sending=true
        Task {
            do {
                let store = try model.requireStore()
                let photos = try visit.photoIDs.map { id -> Data in
                    guard let data = try store.photo(id) else { throw CocoaError(.fileReadNoSuchFile) }
                    return try PhotoService.sanitizedJPEG(data)
                }
                let oldEntries = store.entries(in:target).filter { (try? store.snapshot($0).sourceVisitID) == visit.id }
                try await store.publish(SharedSnapshot(visit:visit),photos:photos,to:target)
                for entry in oldEntries { try store.removeEntry(entry) }
                model.reload(); dismiss()
            } catch { self.error=error.localizedDescription }
            sending=false
        }
    }
}
struct CloudShareController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let store: Persistence?
    let list: NSManagedObject
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context:Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share:share,container:container)
        controller.delegate=context.coordinator
        controller.availablePermissions = [.allowPrivate,.allowReadOnly]
        return controller
    }
    func updateUIViewController(_ uiViewController:UICloudSharingController,context:Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: CloudShareController
        init(_ parent:CloudShareController) { self.parent=parent }
        func itemTitle(for csc:UICloudSharingController) -> String? { parent.list.value(forKey:"title") as? String }
        func cloudSharingController(_ csc:UICloudSharingController,failedToSaveShareWithError error:Error) { parent.onError(error.localizedDescription) }
        func cloudSharingControllerDidSaveShare(_ csc:UICloudSharingController) {
            guard let share=csc.share else { return }
            Task { @MainActor in do { try await parent.store?.persistShare(share,store:parent.list.objectID.persistentStore) } catch { parent.onError(error.localizedDescription) } }
        }
        // iOS 17 Core Data observes the system sharing controller's revocation changes.
        func cloudSharingControllerDidStopSharing(_ csc:UICloudSharingController) {}
    }
}
