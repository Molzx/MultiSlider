//
//  GradientView.swift
//
//
//  Created by xuzhenghao on 2022/11/24.
//

import Foundation
import UIKit

class GradientView: UIView {
    var gradientLayer: CAGradientLayer {
        return self.layer as! CAGradientLayer
    }

    override class var layerClass: AnyClass {
        return CAGradientLayer.classForCoder()
    }
}
