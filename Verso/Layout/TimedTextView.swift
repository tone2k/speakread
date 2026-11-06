import SwiftUI
import UIKit

/// One TextKit 2 text view for a whole chapter or transcript (P5).
///
/// The old transcript was one SwiftUI view per word — a one-hour recording
/// built ~9,000 views and re-measured them as the highlight moved. Here the
/// full text is set once; per spoken word the only work is moving ONE lock
/// layer to the word's rect, recoloring the newly-passed range, and (when
/// following) keeping the lock inside the middle band. Tap maps back to a
/// span through the line segment under the finger; the reading face is
/// monospace, so the character inside a line is arithmetic.
struct TimedTextView: UIViewRepresentable {
    let text: TimedText
    /// Global index of the current span; `text` may be one page of a
    /// chapter, in which case `indexOffset` is the global index of
    /// `text.spans[0]` and all internal indexing is page-local.
    var currentIndex: Int?
    var indexOffset: Int = 0
    var fontSize: CGFloat
    /// Words before the current one are dimmed (playback, listening).
    var dimBefore: Bool = false
    /// Spans carrying a note: they get a small signal knot.
    var noted: Set<Int> = []
    /// Scrolls internally and keeps the lock in the middle band.
    var follows: Bool = false
    /// Global index speech is prepared through. Words after the current one
    /// up to here carry a faint dotted underline: the buffer ahead of the head.
    var bufferedThrough: Int?
    var onTap: ((Int) -> Void)?
    /// The lock line's mid-Y in text-container coordinates, published only
    /// when the line changes (nil when no word of this text is current).
    var onLineMidY: ((CGFloat?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = follows
        textView.showsVerticalScrollIndicator = false
        textView.contentInsetAdjustmentBehavior = .never

        let lock = UIView()
        lock.backgroundColor = UIColor(hex: 0xFF5A1F).withAlphaComponent(0.14)
        lock.isUserInteractionEnabled = false
        let bar = UIView()
        bar.backgroundColor = UIColor(hex: 0xFF5A1F)
        bar.translatesAutoresizingMaskIntoConstraints = false
        lock.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: lock.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: lock.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: lock.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 2),
        ])
        lock.isHidden = true
        textView.addSubview(lock)
        context.coordinator.lockView = lock

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        textView.addGestureRecognizer(tap)
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.signature != Signature(text: text, fontSize: fontSize, noted: noted, dimBefore: dimBefore) {
            coordinator.signature = Signature(text: text, fontSize: fontSize, noted: noted, dimBefore: dimBefore)
            coordinator.installContent(in: textView)
        }
        coordinator.updateLock(in: textView, force: false)
    }

    struct Signature: Equatable {
        var text: TimedText
        var fontSize: CGFloat
        var noted: Set<Int>
        var dimBefore: Bool
    }

    // MARK: Coordinator

    final class Coordinator: NSObject {
        var parent: TimedTextView?
        weak var textView: UITextView?
        var lockView: UIView?
        var signature: Signature?
        private var offsets: [Int] = []
        private var lastLockIndex: Int?
        private var lastDimmedUpTo = 0
        private var lastBuffered: Range<Int> = 0..<0
        private var lastLineMidY: CGFloat?
        private var knotViews: [UIView] = []
        private static let bufferUnderline = UIColor(hex: 0xFF5A1F).withAlphaComponent(0.45)
        private static let bufferStyle = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue

        // MARK: Content

        func installContent(in textView: UITextView) {
            guard let parent else { return }
            let text = parent.text
            offsets = text.characterOffsets()
            let plain = text.plain
            let attributed = NSMutableAttributedString(string: plain)
            let full = NSRange(location: 0, length: (plain as NSString).length)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = HUD.readLineSpacing(parent.fontSize)
            attributed.addAttributes([
                .font: UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular),
                .foregroundColor: UIColor.hudFG0,
                .paragraphStyle: paragraph,
            ], range: full)
            for (index, span) in text.spans.enumerated() {
                // Non-final and low-confidence spans get their own color;
                // the base attributes already carry fg0.
                if !span.isFinal {
                    attributed.addAttribute(.foregroundColor, value: UIColor.hudFG2, range: range(of: index))
                } else if span.confidence < 0.6 {
                    attributed.addAttribute(.foregroundColor, value: UIColor.hudFG1, range: range(of: index))
                }
            }
            textView.attributedText = attributed
            lastDimmedUpTo = 0
            lastBuffered = 0..<0
            lastLockIndex = nil
            lastLineMidY = nil
            installKnots(in: textView)
            updateLock(in: textView, force: true)
        }

        private func baseColor(of span: TimedSpan) -> UIColor {
            guard parent != nil else { return UIColor.hudFG0 }
            if !span.isFinal { return UIColor.hudFG2 }
            if span.confidence < 0.6 { return UIColor.hudFG1 }
            return UIColor.hudFG0
        }

        /// Character range of a PAGE-LOCAL span index.
        private func range(of localIndex: Int) -> NSRange {
            guard let parent, offsets.indices.contains(localIndex) else { return NSRange(location: 0, length: 0) }
            let start = offsets[localIndex]
            let end = localIndex + 1 < offsets.count ? offsets[localIndex + 1] : (parent.text.plain as NSString).length
            return NSRange(location: start, length: max(0, end - start))
        }

        // MARK: Knots

        private func installKnots(in textView: UITextView) {
            knotViews.forEach { $0.removeFromSuperview() }
            knotViews = []
            guard let parent, !parent.noted.isEmpty else { return }
            // Knots need laid-out rects; the text view lays out async, so
            // place them on the next runloop pass, when segments exist.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, let parent = self.parent else { return }
                for global in parent.noted.sorted() {
                    let index = global - parent.indexOffset
                    guard parent.text.spans.indices.contains(index),
                          let rect = self.rect(forSpan: index, in: textView) else { continue }
                    let knot = UIView(frame: CGRect(x: rect.maxX - 5, y: rect.minY + 1, width: 5, height: 5))
                    knot.backgroundColor = UIColor(hex: 0xFF5A1F)
                    knot.isUserInteractionEnabled = false
                    textView.addSubview(knot)
                    self.knotViews.append(knot)
                }
            }
        }

        // MARK: Lock + dimming

        func updateLock(in textView: UITextView, force: Bool) {
            guard let parent, let lockView else { return }
            let count = parent.text.spans.count
            let global = parent.currentIndex
            let local: Int? = global.flatMap { g in
                let l = g - parent.indexOffset
                return parent.text.spans.indices.contains(l) ? l : nil
            }
            // Dimming boundary in local terms: a current word past this
            // page dims the whole page; before it, nothing.
            let dimTarget: Int
            if !parent.dimBefore || global == nil {
                dimTarget = 0
            } else if global! < parent.indexOffset {
                dimTarget = 0
            } else if global! >= parent.indexOffset + count {
                dimTarget = count
            } else {
                dimTarget = global! - parent.indexOffset
            }
            updateDimming(in: textView, upTo: dimTarget)
            updateBuffer(in: textView, count: count)
            guard let current = local else {
                if lastLockIndex != nil || force {
                    lockView.isHidden = true
                    lastLockIndex = nil
                    publishLineMidY(nil)
                }
                return
            }
            guard force || current != lastLockIndex else { return }
            guard let rect = rect(forSpan: current, in: textView) else { return }
            let wasHidden = lockView.isHidden
            let sameLine = !wasHidden && abs(lockView.frame.minY - rect.minY) < 1
            let apply = {
                lockView.frame = rect.insetBy(dx: -1, dy: 0)
                lockView.isHidden = false
            }
            if sameLine {
                UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut], animations: apply)
            } else {
                apply()
            }
            lastLockIndex = current
            publishLineMidY(rect.midY)
            if parent.follows {
                followLock(in: textView, rect: rect)
            }
        }

        private func publishLineMidY(_ y: CGFloat?) {
            if y != lastLineMidY {
                lastLineMidY = y
                parent?.onLineMidY?(y)
            }
        }

        /// Recolors only the delta between the old and new dim boundaries.
        private func updateDimming(in textView: UITextView, upTo target: Int) {
            guard target != lastDimmedUpTo, let parent else { return }
            let storage = textView.textStorage
            storage.beginEditing()
            if target > lastDimmedUpTo {
                for i in lastDimmedUpTo..<min(target, parent.text.spans.count) {
                    storage.addAttribute(.foregroundColor, value: UIColor.hudFG1, range: range(of: i))
                }
            } else {
                for i in target..<lastDimmedUpTo where parent.text.spans.indices.contains(i) {
                    storage.addAttribute(.foregroundColor, value: baseColor(of: parent.text.spans[i]), range: range(of: i))
                }
            }
            storage.endEditing()
            lastDimmedUpTo = target
        }

        /// Underlines the words whose audio is already prepared: from just
        /// after the current word through `bufferedThrough`, clipped to this
        /// page. Only the difference from the last range is touched, so a
        /// new sentence costs a handful of attribute edits, never a page.
        private func updateBuffer(in textView: UITextView, count: Int) {
            guard let parent else { return }
            var target: Range<Int> = 0..<0
            if let through = parent.bufferedThrough, let current = parent.currentIndex, through > current {
                let lower = min(max(current + 1 - parent.indexOffset, 0), count)
                let upper = min(max(through + 1 - parent.indexOffset, 0), count)
                if lower < upper { target = lower..<upper }
            }
            guard target != lastBuffered else { return }
            let storage = textView.textStorage
            storage.beginEditing()
            for i in lastBuffered where !target.contains(i) && parent.text.spans.indices.contains(i) {
                storage.removeAttribute(.underlineStyle, range: range(of: i))
                storage.removeAttribute(.underlineColor, range: range(of: i))
            }
            for i in target where !lastBuffered.contains(i) {
                storage.addAttributes([.underlineStyle: Self.bufferStyle, .underlineColor: Self.bufferUnderline], range: range(of: i))
            }
            storage.endEditing()
            lastBuffered = target
        }

        private func followLock(in textView: UITextView, rect: CGRect) {
            let visibleTop = textView.contentOffset.y
            let visibleHeight = textView.bounds.height
            guard visibleHeight > 0 else { return }
            let bandTop = visibleTop + visibleHeight * 0.2
            let bandBottom = visibleTop + visibleHeight * 0.8
            if rect.midY < bandTop || rect.midY > bandBottom {
                let target = min(
                    max(0, rect.midY - visibleHeight * 0.4),
                    max(0, textView.contentSize.height - visibleHeight)
                )
                if abs(target - visibleTop) > 1 {
                    textView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
                }
            }
        }

        // MARK: Geometry

        /// The laid-out rect of one span, in text-container coordinates
        /// (which match the text view's content coordinates: inset is 0).
        func rect(forSpan index: Int, in textView: UITextView) -> CGRect? {
            let range = range(of: index)
            guard range.length > 0 else { return nil }
            guard let layoutManager = textView.textLayoutManager,
                  let storage = layoutManager.textContentManager as? NSTextContentStorage else { return nil }
            let docRange = storage.documentRange
            guard let start = storage.location(docRange.location, offsetBy: range.location),
                  let end = storage.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { return nil }
            layoutManager.ensureLayout(for: textRange)
            var result: CGRect?
            layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, segmentFrame, _, _ in
                result = segmentFrame
                return false
            }
            return result
        }

        // MARK: Tap

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let parent, let textView, gesture.state == .ended else { return }
            var point = gesture.location(in: textView)
            point.y += textView.contentOffset.y
            // Find the line segment under the finger, then the character
            // inside it (monospace: one char advance per character).
            guard let layoutManager = textView.textLayoutManager,
                  let storage = layoutManager.textContentManager as? NSTextContentStorage else { return }
            let docRange = storage.documentRange
            layoutManager.ensureLayout(for: docRange)
            var hit: (range: NSTextRange, frame: CGRect)?
            layoutManager.enumerateTextSegments(in: docRange, type: .standard, options: []) { segmentRange, segmentFrame, _, _ in
                guard let segmentRange else { return true }
                if segmentFrame.minY <= point.y, point.y <= segmentFrame.maxY + 4 {
                    hit = (segmentRange, segmentFrame)
                    return false
                }
                return segmentFrame.minY <= point.y
            }
            guard let hit else { return }
            let lineStart = storage.offset(from: docRange.location, to: hit.range.location)
            let advance = max(1, parent.fontSize * 0.6)
            let localChar = max(0, Int((point.x - hit.frame.minX) / advance))
            if let span = TimedText.spanIndex(forOffset: lineStart + localChar, offsets: offsets) {
                parent.onTap?(span + parent.indexOffset)
            }
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The HUD text colors, resolving per color scheme (dark values are
    /// the original palette; light values are its inversion).
    static var hudFG0: UIColor {
        UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: 0x16191D) : UIColor(hex: 0xE6EDF3) }
    }
    static var hudFG1: UIColor {
        UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: 0x4B5563) : UIColor(hex: 0x9BA7B4) }
    }
    static var hudFG2: UIColor {
        UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: 0x5D6874) : UIColor(hex: 0x6E7A87) }
    }
}
