import SwiftUI
import XingjiCore
struct TimelineScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var section = 0
    @State private var pendingOnly = false
    private var records: [Visit] { model.visits.filter { !pendingOnly || $0.status == .pending } }
    private var days: [Date] { Set(records.map { Calendar.current.startOfDay(for:$0.arrival) }).sorted(by:>) }
    var body: some View {
        List {
            Section {
                Picker("回顾类型",selection:$section) { Text("到访").tag(0); Text("旅行").tag(1) }.pickerStyle(.segmented)
                if section == 0 {
                    Toggle("只看待确认（\(model.visits.filter { $0.status == .pending }.count)）",isOn:$pendingOnly)
                    if !model.matchStatus.isEmpty { Text(model.matchStatus).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if section == 0 {
                if records.isEmpty { ContentUnavailableView(pendingOnly ? "暂时没有待确认地点" : "还没有到访记录",systemImage:"clock",description:Text("记录开启后，停留会出现在这里。也可以在地图页手动补记。")) }
                ForEach(days,id:\.self) { day in
                    Section(day.formatted(date:.complete,time:.omitted)) {
                        ForEach(records.filter { Calendar.current.isDate($0.arrival,inSameDayAs:day) }) { visit in
                            NavigationLink { VisitDetailScreen(visitID:visit.id) } label: { VisitRow(visit:visit) }
                        }
                    }
                }
            } else {
                if model.trips.isEmpty { ContentUnavailableView("下一段旅程，从这里开始",systemImage:"point.topleft.down.to.point.bottomright.curvepath",description:Text("在地图页开启旅游模式，路线与沿途停留会保存在这里。")) }
                ForEach(model.trips) { trip in
                    NavigationLink { TripDetailScreen(tripID:trip.id) } label: {
                        VStack(alignment:.leading,spacing:8) {
                            Text(trip.title).font(.headline)
                            Text(trip.startedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                            if trip.endedAt == nil { Text("进行中").font(.caption).foregroundStyle(Theme.green) }
                        }.padding(.vertical,6)
                    }
                }
            }
        }.navigationTitle("回顾")
    }
}
struct TripDetailScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var chunks: [TripChunk] = []
    @State private var deleting = false
    private var trip: Trip? { model.trips.first { $0.id == tripID } }
    private var visits: [Visit] {
        guard let trip else { return [] }
        return model.visits.filter { $0.arrival >= trip.startedAt && $0.arrival <= (trip.endedAt ?? Date()) }
    }
    var body: some View {
        Group {
            if let trip {
                List {
                    MapCanvas(visits:visits,chunks:chunks,service:model.mapService).frame(height:300).listRowInsets(EdgeInsets())
                    Section("行程") {
                        LabeledContent("开始",value:trip.startedAt.formatted(date:.abbreviated,time:.shortened))
                        LabeledContent("结束",value:trip.endedAt?.formatted(date:.abbreviated,time:.shortened) ?? "进行中")
                        Text("\(chunks.reduce(0) { $0 + $1.segment.points.count }) 个定位点 · \(visits.count) 次停留").font(.subheadline).foregroundStyle(.secondary)
                        if chunks.isEmpty { Text("尚未收到可用定位点。请检查定位权限与记录状态。").foregroundStyle(.secondary) }
                    }
                    let gaps = chunks.filter { $0.segment.gapBefore != nil }
                    if !gaps.isEmpty {
                        Section("路线分段说明") { ForEach(gaps) { chunk in
                            VStack(alignment:.leading) {
                                Text(chunk.segment.gapBefore ?? "")
                                if let date = chunk.segment.points.first?.date { Text(date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                            }
                        } }
                    }
                    Section("沿途停留") { ForEach(visits) { visit in NavigationLink { VisitDetailScreen(visitID:visit.id) } label: { VisitRow(visit:visit) } } }
                    Section { Button("删除这段旅行路线",role:.destructive) { deleting=true } }
                }.navigationTitle(trip.title).navigationBarTitleDisplayMode(.inline)
                .task { do { model.tracker.flush(); chunks=try model.chunks(for:trip) } catch { model.error=error.localizedDescription } }
                .confirmationDialog("删除旅行路线？店铺到访记录会保留。",isPresented:$deleting,titleVisibility:.visible) { Button("删除路线",role:.destructive) { model.deleteTrip(trip); if model.error == nil { dismiss() } } }
            } else { ContentUnavailableView("旅行已删除",systemImage:"trash") }
        }
    }
}
