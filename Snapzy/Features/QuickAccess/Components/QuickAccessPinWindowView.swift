//
//  QuickAccessPinWindowView.swift
//  Snapzy
//
//  Floating image-first surface for pinned screenshots.
//

import AppKit
import SwiftUI

struct QuickAccessPinWindowView: View {
  @ObservedObject var state: QuickAccessPinWindowState

  var body: some View {
    Image(nsImage: state.image)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: state.displaySize.width, height: state.displaySize.height)
      .clipped()
      .background(Color.clear)
  }
}
