import Foundation

extension DateFormatter {
    static let hm: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()
}
