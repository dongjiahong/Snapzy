//
//  CounterToolIcon.swift
//  Snapzy
//
//  Circled numbered-marker glyph for the counter tool.
//

import SwiftUI

/// Draws a circled "1" matching the counter annotation marker, so the toolbar
/// icon reads as the same object the tool places on the canvas.
struct CounterToolIcon: View {
  var size: CGFloat = 16

  var body: some View {
    ZStack {
      Circle()
        .strokeBorder(lineWidth: size * 0.085)
      Text("1")
        .font(.system(size: size * 0.56, weight: .bold))
        .offset(y: size * 0.015)
    }
    .frame(width: size, height: size)
  }
}
