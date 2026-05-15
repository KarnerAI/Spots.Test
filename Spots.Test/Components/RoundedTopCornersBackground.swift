//
//  RoundedTopCornersBackground.swift
//  Spots.Test
//
//  Shared by ProfileView and UserProfileView. Uses `CALayer.cornerRadius`
//  instead of SwiftUI shapes to avoid animation artifacts from NavigationStack
//  insertion transitions.
//

import SwiftUI
import UIKit

struct RoundedTopCornersBackground: UIViewRepresentable {
    let radius: CGFloat

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = radius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.cornerCurve = .continuous
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        uiView.layer.cornerRadius = radius
        CATransaction.commit()
    }
}
