import SwiftUI
import XingjiCore

struct MapScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: Visit?
    @State private var add = false
    @State private var filter = false
    @State private var status: MatchStatus?
    @State private var minimumRating = 0.0
    @State private var dateEnabled = false
    @State private var date = Date()
    private var filtered: [Visit] {
        model.visits.filter { visit in
            (status == nil || visit.status == status) && (minimumRating == 0 || (visit.rating ?? 0) >= minimumRating) && (!dateEnabled || Calendar.current.isDate(visit.arrival,inSameDayAs:date))
        }
    }
    private var markers: [Visit] {
        var seen = Set<String>()
        return filtered.filter { seen.insert($0.place?.id ?? $0.id.uuidString).inserted }
    }
    var body: some View {
        VStack(spacing:0) {
            MapCanvas(visits:markers,chunks:model.activeRoute,service:model.mapService) { selected = $0 }.frame(maxHeight:.infinity)
            VStack(spacing:12) {
                if model.visits.isEmpty && model.mapService.available {
                    Text("开启记录，或用右上角 + 添加第一家店").font(.subheadline).padding(14).background(.regularMaterial,in:Capsule())
                }
                RecordingCard(tracker:model.tracker)
            }.padding(16)
        }
        .navigationTitle("行迹").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.topBarLeading) { Text("\(markers.count) 个地点").font(.subheadline).foregroundStyle(.secondary) }
            ToolbarItemGroup(placement:.topBarTrailing) {
                Button { filter = true } label: { Image(systemName:"line.3.horizontal.decrease.circle") }.accessibilityLabel("筛选地图")
                Button { add = true } label: { Image(systemName:"plus") }.accessibilityLabel("手动添加记录")
            }
        }
        .sheet(item:$selected) { visit in NavigationStack { PlaceHistoryScreen(visit:visit) }.environmentObject(model) }
        .sheet(isPresented:$add) { NavigationStack { VisitEditor(visit:nil) }.environmentObject(model) }
        .sheet(isPresented:$filter) {
            NavigationStack {
                Form {
                    Picker("记录状态",selection:$status) { Text("全部").tag(MatchStatus?.none); ForEach(MatchStatus.allCases,id:\.self) { Text($0.label).tag(Optional($0)) } }
                    Picker("最低评分",selection:$minimumRating) { Text("不限").tag(0.0); ForEach([3.0,3.5,4.0,4.5,5.0],id:\.self) { Text(String(format:"%.1f 星",$0)).tag($0) } }
                    Toggle("按日期筛选",isOn:$dateEnabled)
                    if dateEnabled { DatePicker("日期",selection:$date,displayedComponents:.date) }
                    Button("重置筛选") { status=nil; minimumRating=0; dateEnabled=false }
                }.navigationTitle("筛选").toolbar { Button("完成") { filter=false } }
            }.presentationDetents([.medium])
        }
    }
}
struct PlaceHistoryScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    private var history: [Visit] { model.visits.filter { visit.place != nil ? $0.place?.id == visit.place?.id : $0.id == visit.id } }
    var body: some View {
        List {
            Section {
                Text(visit.place?.address ?? "确认店铺后，可在这里回顾每次到访。").foregroundStyle(.secondary)
                HStack {
                    Label("\(history.count) 次到访",systemImage:"clock")
                    Spacer()
                    if let average = Rating.average(history.map(\.rating)) { Label(String(format:"%.1f",average),systemImage:"star.fill").foregroundStyle(Theme.orange) }
                }
            }
            Section("到访记录") { ForEach(history) { item in NavigationLink { VisitDetailScreen(visitID:item.id) } label: { VisitRow(visit:item) } } }
        }.navigationTitle(visit.title).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("完成") { dismiss() } } }
    }
}
