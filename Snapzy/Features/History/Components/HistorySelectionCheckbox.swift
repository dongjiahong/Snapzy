//
//  HistorySelectionCheckbox.swift
//  Snapzy
//
//  Compact checkbox overlay used by history cards for multi-select.
//

import SwiftUI

struct HistorySelectionCheckbox: View {
  let isChecked: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(isChecked ? .white : .white.opacity(0.92))
        .padding(2)
        .background(
          Circle()
            .fill(isChecked ? Color.accentColor : Color.black.opacity(0.45))
        )
        .overlay(
          Circle()
            .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .help(isChecked ? L10n.PreferencesHistory.clearSelection : L10n.PreferencesHistory.selectAll)
  }
}
