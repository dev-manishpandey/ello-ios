////
///  Line.swift
//

class Line: UIView {
    enum Orientation {
        case horizontal
        case vertical
    }
    private let orientation: Orientation

    var thickness: CGFloat = 1 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize {
        switch orientation {
        case .horizontal: return CGSize(width: UIViewNoIntrinsicMetric, height: thickness)
        case .vertical: return CGSize(width: thickness, height: UIViewNoIntrinsicMetric)
        }
    }

    init(orientation: Orientation = .horizontal, color: UIColor? = nil) {
        self.orientation = orientation
        super.init(frame: .zero)
        if let color = color {
            self.backgroundColor = color
        }
    }

    override init(frame: CGRect) {
        self.orientation = .horizontal
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        self.orientation = .horizontal
        super.init(coder: coder)
    }
}
