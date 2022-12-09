//
//  MultiSlider.swift
//  UISlider clone with multiple thumbs and values, and optional snap intervals.
//
//  Created by Yonat Sharon on 14.11.2016.
//  Copyright © 2016 Yonat Sharon. All rights reserved.
//

import AvailableHapticFeedback
import SweeterSwift
import UIKit

@IBDesignable
open class MultiSlider: UIControl {
    @objc open var value: [CGFloat] = [] {
        didSet {
            if isSettingValue { return }
            adjustThumbCountToValueCount()
            adjustValuesToStepAndLimits()
            updateAllValueLabels()
            accessibilityValue = value.description
        }
    }

    @objc public internal(set) var draggedThumbIndex: Int = -1

    @IBInspectable open dynamic var minimumValue: CGFloat = 0 { didSet { adjustValuesToStepAndLimits() } }
    @IBInspectable open dynamic var maximumValue: CGFloat = 1 { didSet { adjustValuesToStepAndLimits() } }
    @IBInspectable open dynamic var isContinuous: Bool = true

    /// snap thumbs to specific values, evenly spaced. (default = 0: allow any value)
    @IBInspectable open dynamic var snapStepSize: CGFloat = 0 { didSet { adjustValuesToStepAndLimits() } }

    /// generate haptic feedback when hitting snap steps
    @IBInspectable open dynamic var isHapticSnap: Bool = true

    @IBInspectable open dynamic var thumbCount: Int {
        get {
            return thumbViews.count
        }
        set {
            guard newValue > 0 else { return }
            updateValueCount(newValue)
            adjustThumbCountToValueCount()
        }
    }

    /// make specific thumbs fixed (and grayed)
    @objc open var disabledThumbIndices: Set<Int> = [] {
        didSet {
            for i in 0 ..< thumbCount {
                thumbViews[i].blur(disabledThumbIndices.contains(i))
            }
        }
    }

    /// show value labels next to thumbs. (default: show no label)
    @objc open dynamic var valueLabelPosition: NSLayoutConstraint.Attribute = .notAnAttribute {
        didSet {
            valueLabels.removeViewsStartingAt(0)
            if valueLabelPosition != .notAnAttribute {
                for i in 0 ..< thumbViews.count {
                    addValueLabel(i)
                }
            }
        }
    }
    
    /// set value label margin to the slider
    open dynamic var valueLabelMargin: CGFloat? {
        didSet {
            valueLabels.removeViewsStartingAt(0)
            if valueLabelPosition != .notAnAttribute {
                for i in 0 ..< thumbViews.count {
                    addValueLabel(i)
                }
            }
        }
    }

    /// value label shows difference from previous thumb value (true) or absolute value (false = default)
    @IBInspectable open dynamic var isValueLabelRelative: Bool = false {
        didSet {
            updateAllValueLabels()
        }
    }

    // MARK: - Appearance

    @IBInspectable open dynamic var isVertical: Bool {
        get { return orientation == .vertical }
        set { orientation = newValue ? .vertical : .horizontal }
    }

    @objc open dynamic var orientation: NSLayoutConstraint.Axis = .vertical {
        didSet {
            let oldConstraintAttribute: NSLayoutConstraint.Attribute = oldValue == .vertical ? .width : .height
            removeFirstConstraint(where: { $0.firstAttribute == oldConstraintAttribute && $0.firstItem === self && $0.secondItem == nil })
            setupOrientation()
            invalidateIntrinsicContentSize()
            repositionThumbViews()
        }
    }

    /// track color before first thumb and after last thumb. `nil` means to use the tintColor, like the rest of the track.
    @IBInspectable open dynamic var outerTrackColor: UIColor? {
        didSet {
            updateOuterTrackViews()
        }
    }

    @IBInspectable open dynamic var valueLabelColor: UIColor? {
        didSet {
            valueLabels.forEach { $0.textColor = valueLabelColor }
        }
    }

    open dynamic var valueLabelFont: UIFont? {
        didSet {
            valueLabels.forEach { $0.font = valueLabelFont }
        }
    }

    @IBInspectable public dynamic var thumbTintColor: UIColor? {
        didSet {
            thumbViews.forEach { $0.applyTint(color: thumbTintColor) }
        }
    }

    @IBInspectable open dynamic var thumbImage: UIImage? {
        didSet {
            thumbViews.forEach { $0.image = thumbImage }
            setupTrackLayoutMargins()
            invalidateIntrinsicContentSize()
        }
    }

    @IBInspectable public dynamic var showsThumbImageShadow: Bool = true {
        didSet {
            updateThumbViewShadowVisibility()
        }
    }

    @IBInspectable open dynamic var minimumImage: UIImage? {
        get {
            return minimumView.image
        }
        set {
            minimumView.image = newValue
            minimumView.isHidden = newValue == nil
            layoutTrackEdge(
                toView: minimumView,
                edge: .bottom(in: orientation),
                superviewEdge: orientation == .vertical ? .bottomMargin : .leftMargin
            )
        }
    }

    @IBInspectable open dynamic var maximumImage: UIImage? {
        get {
            return maximumView.image
        }
        set {
            maximumView.image = newValue
            maximumView.isHidden = newValue == nil
            layoutTrackEdge(
                toView: maximumView,
                edge: .top(in: orientation),
                superviewEdge: orientation == .vertical ? .topMargin : .rightMargin
            )
        }
    }

    @IBInspectable open dynamic var trackWidth: CGFloat = 2 {
        didSet {
            let widthAttribute: NSLayoutConstraint.Attribute = orientation == .vertical ? .width : .height
            trackView.removeFirstConstraint { $0.firstAttribute == widthAttribute }
            trackView.constrain(widthAttribute, to: trackWidth)
            updateTrackViewCornerRounding()
        }
    }

    @IBInspectable public dynamic var hasRoundTrackEnds: Bool = true {
        didSet {
            updateTrackViewCornerRounding()
        }
    }

    /// minimal distance to keep between thumbs (half a thumb by default)
    @IBInspectable public dynamic var distanceBetweenThumbs: CGFloat = -1

    @IBInspectable public dynamic var keepsDistanceBetweenThumbs: Bool {
        get { return distanceBetweenThumbs != 0 }
        set {
            if keepsDistanceBetweenThumbs != newValue {
                distanceBetweenThumbs = newValue ? -1 : 0
            }
        }
    }

    @objc open dynamic var valueLabelFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        formatter.roundingMode = .halfEven
        return formatter
    }() {
        didSet {
            updateAllValueLabels()
            if #available(iOS 11.0, *) {
                oldValue.removeObserverForAllProperties(observer: self)
                valueLabelFormatter.addObserverForAllProperties(observer: self)
            }
        }
    }

    /// Return value label text for a thumb index and value. If `nil`, then `valueLabelFormatter` will be used instead.
    @objc open dynamic var valueLabelTextForThumb: ((Int, CGFloat) -> String?)? {
        didSet {
            for i in valueLabels.indices {
                updateValueLabel(i)
            }
        }
    }
    
    @IBInspectable public dynamic var hideThumb: Bool = false {
        didSet {
            thumbImage = nil
            tintColor = .clear
            thumbTintColor = .clear
//            updateInnerTrackView()
        }
    }
    
    @IBInspectable public dynamic var showInnerTrackGradientLayer: Bool = false {
        didSet {
//            updateInnerTrackView()
        }
    }
    
    @objc open dynamic var innerTrackGradientLayer: CAGradientLayer {
        return innerTrackView.gradientLayer
    }
    
    @IBInspectable open dynamic var trackColor: UIColor? {
        didSet {
            slideView.backgroundColor = trackColor
        }
    }
    
    
    /// disabled drag if true
    @IBInspectable public dynamic var disabledDragGesture: Bool = false

    // MARK: - Subviews

    @objc open var thumbViews: [UIImageView] = []
    @objc open var valueLabels: [UITextField] = [] // UILabels are a pain to layout, text fields look nice as-is.
    @objc open var trackView = UIView()
    @objc open var outerTrackViews: [UIView] = []
    @objc open var minimumView = UIImageView()
    @objc open var maximumView = UIImageView()

    // MARK: - Internals

    let slideView = UIView()
    let panGestureView = UIView()
    ///Will affect the gesture touch area
    let margin: CGFloat = 0
    var isSettingValue = false
    lazy var defaultThumbImage: UIImage? = .circle()
    var selectionFeedbackGenerator = AvailableHapticFeedback()

    
    lazy var innerTrackView: GradientView = {
        let view = GradientView()
        view.gradientLayer.colors = [UIColor.blue.cgColor, UIColor.red.cgColor]
        view.gradientLayer.locations = [0, 1]
        view.gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        view.gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        return view
    }()
    
    // MARK: - Overrides

    override open func tintColorDidChange() {
        let thumbTint = thumbViews.map { $0.tintColor } // different thumbs may have different tints
        super.tintColorDidChange()
        let actualColor = actualTintColor
        trackView.backgroundColor = actualColor
        minimumView.tintColor = actualColor
        maximumView.tintColor = actualColor
        for (thumbView, tint) in zip(thumbViews, thumbTint) {
            thumbView.tintColor = tint
        }
    }

    override open var intrinsicContentSize: CGSize {
        let thumbSize = (thumbImage ?? defaultThumbImage)?.size ?? CGSize(width: margin, height: margin)
        switch orientation {
        case .vertical:
            return CGSize(width: thumbSize.width + margin, height: UIView.noIntrinsicMetric)
        default:
            return CGSize(width: UIView.noIntrinsicMetric, height: thumbSize.height + margin)
        }
    }

    override open func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isHidden || alpha == 0 { return nil }
        if clipsToBounds { return super.hitTest(point, with: event) }
        return panGestureView.hitTest(panGestureView.convert(point, from: self), with: event)
    }

    // swiftlint:disable:next block_based_kvo
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if object as? NumberFormatter === valueLabelFormatter {
            updateAllValueLabels()
        }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        if #available(iOS 11.0, *) {
            valueLabelFormatter.removeObserverForAllProperties(observer: self)
        }
    }

    override open func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()

        // make visual editing easier
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.lightGray.withAlphaComponent(0.5).cgColor

        // evenly distribute thumbs
        let oldThumbCount = thumbCount
        thumbCount = 0
        thumbCount = oldThumbCount
    }
}
