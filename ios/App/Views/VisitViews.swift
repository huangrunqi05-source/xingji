import SwiftUI
import PhotosUI
import XingjiCore

struct VisitDetailScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let visitID: UUID
    @State private var editing = false
    @State private var choosingPlace = false
    @State private var publishing = false
    @State private var deleting = false
    @State private var ignoring = false
    @State private var matching = false
    private var visit: Visit? { model.visits.first { $0.id == visitID } }
    var body: some View {
        Group {
            if let visit {
                List {
                    Section {
                        HStack { Text(visit.title).font(.title2.bold()); Spacer(); StatusBadge(status:visit.status) }
                        if let address = visit.place?.address { Text(address).foregroundStyle(.secondary) }
                        LabeledContent("到达",value:visit.arrival.formatted(date:.abbreviated,time:.shortened))
                        if let departure = visit.departure { LabeledContent("离开",value:departure.formatted(date:.abbreviated,time:.shortened)) }
                        LabeledContent("来源",value:visit.source == .manual ? "手动补记" : "自动识别停留")
                    }
                    if visit.status == .pending {
                        Section("确认是哪一家店") {
                            if visit.candidates.isEmpty { Text("没有可靠匹配。可以重试附近查询，或手动搜索店铺。").foregroundStyle(.secondary) }
                            ForEach(visit.candidates) { place in
                                Button { model.confirm(visit,place:place) } label: { VStack(alignment:.leading) { Text(place.name); Text(place.address).font(.caption).foregroundStyle(.secondary) } }
                            }
                            Button(matching ? "正在查询…" : "重新查询附近店铺") { matching=true; Task { await model.retryMatch(visit); matching=false } }.disabled(matching)
                        }
                    }
                    Section("这次体验") {
                        if let rating = visit.rating { Label(String(format:"%.1f / 5",rating),systemImage:"star.fill").foregroundStyle(Theme.orange) }
                        else { Text("还没有评分").foregroundStyle(.secondary) }
                        if !visit.note.isEmpty { Text(visit.note).textSelection(.enabled) }
                        if !visit.photoIDs.isEmpty {
                            ScrollView(.horizontal) { HStack { ForEach(visit.photoIDs,id:\.self) { id in PhotoThumbnail(data:try? model.store?.photo(id)) } } }.listRowSeparator(.hidden)
                        }
                        Button("添加评分、照片或感受") { editing=true }
                    }
                    Section {
                        Button("更正店铺") { choosingPlace=true }
                        Button("加入共享清单") { publishing=true }.disabled(visit.place == nil)
                        Button("忽略此地点") { ignoring=true }
                        Button("删除这条记录",role:.destructive) { deleting=true }
                    }
                }
                .sheet(isPresented:$editing) { NavigationStack { VisitEditor(visit:visit) }.environmentObject(model) }
                .sheet(isPresented:$choosingPlace) { NavigationStack { PlaceSearchSheet { model.confirm(visit,place:$0) } }.environmentObject(model) }
                .sheet(isPresented:$publishing) { NavigationStack { PublishSheet(visit:visit) }.environmentObject(model) }
                .confirmationDialog("删除这条记录及其照片？已分享的副本也会撤回。",isPresented:$deleting,titleVisibility:.visible) {
                    Button("删除记录",role:.destructive) { model.perform { try model.requireStore().deleteVisit(visit) }; if model.error == nil { dismiss() } }
                }
                .confirmationDialog("以后不再自动记录这个地点附近 100 米内的停留，同时删除这条记录。",isPresented:$ignoring,titleVisibility:.visible) {
                    Button("忽略此地点",role:.destructive) { model.ignore(visit); if model.error == nil { dismiss() } }
                }
            } else { ContentUnavailableView("记录已删除",systemImage:"trash") }
        }.navigationTitle("到访记录").navigationBarTitleDisplayMode(.inline)
    }
}
struct VisitEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: Visit?
    @State private var draft: Visit
    @State private var hasDeparture: Bool
    @State private var departure: Date
    @State private var hasRating: Bool
    @State private var rating: Double
    @State private var search = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var newPhotos: [Data] = []
    @State private var removedPhotos: [UUID] = []
    @State private var photoLoading = false
    @State private var error: String?
    init(visit: Visit?) {
        original=visit
        _draft=State(initialValue:visit ?? Visit(arrival:Date(),coordinate:Coordinate(0,0),source:.manual,status:.confirmed))
        _hasDeparture=State(initialValue:visit?.departure != nil); _departure=State(initialValue:visit?.departure ?? Date())
        _hasRating=State(initialValue:visit?.rating != nil); _rating=State(initialValue:visit?.rating ?? 4)
    }
    var body: some View {
        Form {
            Section("地点与时间") {
                Button { search=true } label: { LabeledContent("店铺",value:draft.place?.name ?? "搜索并选择店铺") }
                DatePicker("到达时间",selection:$draft.arrival,in:...Date())
                Toggle("记录离开时间",isOn:$hasDeparture)
                if hasDeparture { DatePicker("离开时间",selection:$departure,in:...Date()) }
            }
            Section("这次体验") {
                Toggle("评分",isOn:$hasRating)
                if hasRating {
                    HStack { Image(systemName:"star.fill").foregroundStyle(Theme.orange); Text(String(format:"%.1f 分",rating)); Slider(value:$rating,in:0.5...5,step:0.5).accessibilityLabel("评分") }
                }
                TextField("味道、服务，或想记住的小事…",text:$draft.note,axis:.vertical).lineLimit(4...10)
            }
            Section("照片 · 最多 12 张") {
                ScrollView(.horizontal) {
                    HStack(alignment:.top) {
                        ForEach(draft.photoIDs.filter { !removedPhotos.contains($0) },id:\.self) { id in
                            VStack { PhotoThumbnail(data:try? model.store?.photo(id)); Button("移除",role:.destructive) { removedPhotos.append(id) }.font(.caption) }
                        }
                        ForEach(Array(newPhotos.enumerated()),id:\.offset) { index,data in
                            VStack { PhotoThumbnail(data:data); Button("移除",role:.destructive) { newPhotos.remove(at:index) }.font(.caption) }
                        }
                    }
                }
                if photoLoading { ProgressView("正在读取照片…") }
                PhotosPicker(selection:$photoSelection,maxSelectionCount:max(1,12-draft.photoIDs.count+removedPhotos.count-newPhotos.count),matching:.images) { Label("从相册添加",systemImage:"photo.badge.plus") }
                    .disabled(photoLoading || draft.photoIDs.count-removedPhotos.count+newPhotos.count >= 12)
            }
        }
        .navigationTitle(original == nil ? "记下一家店" : "编辑记录").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement:.confirmationAction) {
                Button("保存") {
                    draft.rating=hasRating ? rating : nil; draft.departure=hasDeparture ? departure : nil
                    do { try model.saveVisit(draft,addedPhotos:newPhotos,removedPhotos:removedPhotos); dismiss() } catch { self.error=error.localizedDescription }
                }.disabled(photoLoading || (original == nil && draft.place == nil))
            }
        }
        .sheet(isPresented:$search) { NavigationStack { PlaceSearchSheet { place in draft.place=place; draft.status = .confirmed; if original == nil { draft.coordinate=place.coordinate } } }.environmentObject(model) }
        .onChange(of:photoSelection) { _,selection in
            guard !selection.isEmpty else { return }
            photoLoading=true
            Task {
                do {
                    for item in selection {
                        if let data = try await item.loadTransferable(type:Data.self) { newPhotos.append(try PhotoService.sanitizedJPEG(data)) }
                    }
                } catch { self.error=error.localizedDescription }
                photoSelection=[]; photoLoading=false
            }
        }
        .modifier(ErrorAlert(message:$error))
    }
}
struct PlaceSearchSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Place) -> Void
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            Section { TextField("城市 + 店名，例如 上海 咖啡",text:$query).submitLabel(.search).onSubmit { search() }; Button("搜索店铺") { search() }.disabled(query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || loading) }
            if loading { ProgressView("正在搜索…") }
            if !model.mapService.available { Text("高德服务尚未配置，暂不能搜索真实店铺。").foregroundStyle(.secondary) }
            ForEach(results) { place in Button { onSelect(place); dismiss() } label: { VStack(alignment:.leading,spacing:5) { Text(place.name).foregroundStyle(.primary); Text(place.address).font(.caption).foregroundStyle(.secondary) } } }
            if !loading, results.isEmpty, !query.isEmpty { Text("请搜索并选择具体分店，以免记录到同名店铺。").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("选择店铺").toolbar { Button("取消") { dismiss() } }.modifier(ErrorAlert(message:$error))
    }
    private func search() {
        loading=true; let term=query
        Task {
            do { let found=try await model.mapService.search(term); if query == term { results=found } }
            catch { self.error=error.localizedDescription }
            loading=false
        }
    }
}
