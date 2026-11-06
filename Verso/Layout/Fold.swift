import SwiftUI

/// What the device is doing, read from the space the app has and the reserved
/// regions iOS reports. Verso never branches on the device model.
enum Pose: Equatable {
    /// Compact width: the closed phone, or any ordinary iPhone.
    case closed
    /// Open flat, fold vertical: two pages side by side.
    case openWide
    /// Open flat, fold horizontal: one tall page.
    case openTall
    /// Partly folded, fold vertical: held like a book.
    case book
    /// Partly folded, fold horizontal: set down like a laptop.
    case laptop

    var isOpen: Bool { self != .closed }
    var foldIsVertical: Bool { self == .openWide || self == .book }
    var foldIsActive: Bool { self == .book || self == .laptop }
}

/// The fold for one layout pass.
struct Fold: Equatable {
    var pose: Pose
    /// The region to keep clear. For a flat device this is the inactive spine.
    /// Nil when there is no fold at all (an iPad, or a compact window).
    var frame: CGRect?
    var size: CGSize

    /// Width of the left page, or the full width when there is no vertical fold.
    var leadingWidth: CGFloat {
        guard let frame, pose.foldIsVertical else { return size.width }
        return max(0, frame.minX)
    }

    var trailingWidth: CGFloat {
        guard let frame, pose.foldIsVertical else { return 0 }
        return max(0, size.width - frame.maxX)
    }

    var gutterWidth: CGFloat {
        guard let frame, pose.foldIsVertical else { return 0 }
        return frame.width
    }

    var topHeight: CGFloat {
        guard let frame, !pose.foldIsVertical else { return size.height }
        return max(0, frame.minY)
    }

    var bottomHeight: CGFloat {
        guard let frame, !pose.foldIsVertical else { return 0 }
        return max(0, size.height - frame.maxY)
    }

    var gutterHeight: CGFloat {
        guard let frame, !pose.foldIsVertical else { return 0 }
        return frame.height
    }
}

extension GeometryProxy {
    /// Reads the fold. Active regions win (book and laptop poses). When the
    /// device is flat, the inactive division is the spine. Without any division,
    /// a wide window gets a synthetic spine in the middle so the two-page layout
    /// still works on iPad and in the simulator.
    func fold(horizontalSizeClass: UserInterfaceSizeClass?) -> Fold {
        let size = self.size
        if horizontalSizeClass == .compact || size.width < 500 {
            return Fold(pose: .closed, frame: nil, size: size)
        }
        if let active = reservedRegions(kind: .division).first {
            let f = active.frame
            return Fold(pose: f.width < f.height ? .book : .laptop, frame: f, size: size)
        }
        if let inactive = reservedRegions(kind: .division, options: [.includeInactive]).first {
            let f = inactive.frame
            return Fold(pose: f.width < f.height ? .openWide : .openTall, frame: f, size: size)
        }
        if size.width > size.height {
            let spine = CGRect(x: size.width / 2 - 20, y: 0, width: 40, height: size.height)
            return Fold(pose: .openWide, frame: spine, size: size)
        }
        return Fold(pose: .openTall, frame: nil, size: size)
    }
}

/// Two views on either side of the fold. The gutter is the calibrated
/// seam; on a vertical seam the signal trace runs down it to the line
/// being read (`traceY`, in spread coordinates; the stub points toward
/// the pane holding the line).
struct Spread<Leading: View, Trailing: View>: View {
    let fold: Fold
    var traceY: CGFloat?
    var traceLeading: Bool = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if fold.pose.foldIsVertical, fold.frame != nil {
            HStack(spacing: 0) {
                leading.frame(width: fold.leadingWidth)
                ZStack {
                    Seam(axis: .vertical, isActive: fold.pose.foldIsActive)
                    SeamTrace(lineMidY: traceY, stubLeading: traceLeading)
                }
                .frame(width: fold.gutterWidth)
                trailing.frame(width: fold.trailingWidth)
            }
        } else if fold.frame != nil {
            VStack(spacing: 0) {
                leading.frame(height: fold.topHeight)
                Seam(axis: .horizontal, isActive: fold.pose.foldIsActive)
                    .frame(height: fold.gutterHeight)
                trailing.frame(height: fold.bottomHeight)
            }
        } else {
            VStack(spacing: 0) {
                leading
                trailing
            }
        }
    }
}
