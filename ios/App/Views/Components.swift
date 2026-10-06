import SwiftUI
import UIKit
import XingjiCore

enum Theme {
    static let green = Color(red: 0.17, green: 0.38, blue: 0.32)
    static let orange = Color(red: 0.84, green: 0.43, blue: 0.24)
    static let cream = Color(uiColor: .systemGroupedBackground)
}
extension MatchStatus {
    var label: String { switch self { case .pending: return "待确认"; case .inferred: return "自动标记"; case .confirmed: return "已确认" } }
}
struct StatusBadge: View {
    let status: MatchStatus
    var body: some View { Text(status.label).font(.caption2.weight(.medium)).foregroundStyle(status == .pending ? Theme.orange : Theme.green).padding(.horizontal,8).padding(.vertical,4).background((status == .pending ? Theme.orange : Theme.green).opacity(0.1), in: Capsule()) }
}
struct VisitRow: View {
    let visit: Visit
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: visit.status == .pending ? "mappin.and.ellipse" : "fork.knife").font(.title3).foregroundStyle(Theme.green)
                .frame(width:44,height:44).background(Theme.green.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
            VStack(alignment:.leading,spacing:5) {
                Text(visit.title).font(.headline)
                Text(visit.arrival.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                if let rating = visit.rating { Label(String(format:"%.1f",rating),systemImage:"star.fill").font(.caption).foregroundStyle(Theme.orange) }
            }
            Spacer(); StatusBadge(status:visit.status)
        }.padding(.vertical,4)
    }
}
struct PhotoThumbnail: View {
    let data: Data?
    var body: some View {
        Group { if let data, let image = UIImage(data:data) { Image(uiImage:image).resizable().scaledToFill() } else { Image(systemName:"photo").frame(maxWidth:.infinity,maxHeight:.infinity).foregroundStyle(.secondary) } }
            .frame(width:86,height:86).background(.quaternary).clipShape(RoundedRectangle(cornerRadius:12))
    }
}
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?
    func makeUIViewController(context:Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems:items,applicationActivities:nil)
        controller.completionWithItemsHandler = { _,_,_,_ in onComplete?() }; return controller
    }
    func updateUIViewController(_ uiViewController:UIActivityViewController, context:Context) {}
}
struct ErrorAlert: ViewModifier {
    @Binding var message: String?
    func body(content:Content) -> some View {
        content.alert("暂时无法完成",isPresented:Binding(get:{message != nil},set:{if !$0 {message=nil}})) { Button("知道了",role:.cancel) { message=nil } } message: { Text(message ?? "") }
    }
}
