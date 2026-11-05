import SwiftUI

/// Splits a chapter into pages that fit a given page size. An estimate, not a
/// measurement, so it is cheap enough to redo on every fold change.
struct Pagination: Equatable {
    var starts: [Int]
    var total: Int

    static let empty = Pagination(starts: [0], total: 0)

    init(starts: [Int], total: Int) {
        self.starts = starts
        self.total = total
    }

    init(text: TimedText, pageSize: CGSize, fontSize: CGFloat) {
        let charWidth = fontSize * 0.5
        let lineHeight = fontSize * 1.56 + 6
        let charsPerLine = max(10, Int(pageSize.width / charWidth))
        let lines = max(3, Int(pageSize.height / lineHeight))
        let capacity = Int(Double(charsPerLine * lines) * 0.88)
        var starts: [Int] = [0]
        var used = 0
        var lineUsed = 0
        for (i, span) in text.spans.enumerated() {
            let length = span.text.count
            // A word that will not fit on this line wraps and wastes the rest of the line.
            if lineUsed + length > charsPerLine {
                used += charsPerLine - lineUsed
                lineUsed = 0
            }
            if used + length > capacity, i > starts.last! {
                starts.append(i)
                used = 0
                lineUsed = 0
            }
            used += length
            lineUsed += length
            if span.text.contains("\n") {
                used += charsPerLine - lineUsed
                lineUsed = 0
            }
        }
        self.starts = starts
        self.total = text.spans.count
    }

    var pageCount: Int { starts.count }

    func page(containing index: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= index { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func range(ofPage page: Int) -> Range<Int> {
        guard starts.indices.contains(page) else { return 0..<0 }
        let start = starts[page]
        let end = page + 1 < starts.count ? starts[page + 1] : total
        return start..<end
    }
}
