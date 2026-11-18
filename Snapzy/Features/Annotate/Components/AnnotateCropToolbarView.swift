//
//  CropToolbarView.swift
//  Snapzy
//
//  Bottom control surface for crop tool with aspect ratio presets and grid toggle
//

import SwiftUI

/// Shared snapping glyph: crop toolbar, highlighter quick properties, and
/// annotate preferences all use it so "snapping" reads the same everywhere.
enum CropToolbarSymbols {
  /// `magnet` is SF Symbols 5 (macOS 14+); fall back on macOS 13.
  static let snapToEdges =
    NSImage(systemSymbolName: "magnet", accessibilityDescription: nil) != nil ? "magnet" : "square.dashed"
}

/// Bottom control surface displayed while crop mode owns the shared bottom action slot.
struct CropToolbarView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    HStack(spacing: 10) {
      // Aspect ratio picker
      aspectRatioPicker

      Divider()
        .frame(height: 20)

      // Grid toggle
      gridToggle

      // Snap-to-edges toggle
      snapToggle

      // Auto-crop to content (same as the `A` shortcut)
      autoCropButton

      Divider()
        .frame(height: 20)

      // Fill color for expanded crop
      CropFillColorButton(selectedColor: $state.cropFillColor)
    }
  }

  // MARK: - Aspect Ratio Picker

  private var aspectRatioPicker: some View {
    HStack(spacing: 4) {
      ForEach(CropAspectRatio.allCases) { ratio in
        CropRatioButton(
          ratio: ratio,
          isSelected: state.cropAspectRatio == ratio,
          isPortrait: state.isCropPortraitOrientation
        ) {
          state.applyCropAspectRatio(ratio)
        }
      }

      if state.cropAspectRatio != .free, state.cropAspectRatio != .square {
        Divider()
          .frame(height: 20)

        orientationToggle
      }
    }
  }

  // MARK: - Orientation Toggle

  private var orientationToggle: some View {
    Button {
      state.toggleCropOrientation()
    } label: {
      Image(systemName: state.isCropPortraitOrientation ? "rectangle.portrait" : "rectangle")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.accentColor)
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.2))
        )
    }
    .buttonStyle(.plain)
    .help(L10n.AnnotateUI.toggleCropOrientation)
  }

  // MARK: - Grid Toggle

  private var gridToggle: some View {
    Button {
      state.showCropGrid.toggle()
    } label: {
      Image(systemName: state.showCropGrid ? "grid" : "grid.circle")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(state.showCropGrid ? Color.accentColor : Color.primary)
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(state.showCropGrid ? Color.accentColor.opacity(0.2) : Color.clear)
        )
    }
    .buttonStyle(.plain)
    .help(L10n.AnnotateUI.toggleRuleOfThirdsGrid)
  }

  // MARK: - Snap Toggle

  private var snapToggle: some View {
    Button {
      state.isCropEdgeSnappingEnabled.toggle()
    } label: {
      Image(systemName: CropToolbarSymbols.snapToEdges)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(state.isCropEdgeSnappingEnabled ? Color.accentColor : Color.primary)
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(state.isCropEdgeSnappingEnabled ? Color.accentColor.opacity(0.2) : Color.clear)
        )
    }
    .buttonStyle(.plain)
    .help("\(L10n.AnnotateUI.cropSnapToEdges) — \(L10n.AnnotateUI.cropSnapToEdgesHint)")
  }

  // MARK: - Auto-Crop Button

  private var autoCropButton: some View {
    Button {
      Task { @MainActor in
        await state.autoCropToContent()
      }
    } label: {
      Image(systemName: "arrow.up.left.and.arrow.down.right")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.primary)
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.plain)
    .help(L10n.AnnotateUI.autoCropToContent)
  }
}

// MARK: - Aspect Ratio Button

struct CropRatioButton: View {
  let ratio: CropAspectRatio
  let isSelected: Bool
  let isPortrait: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Text(displayName)
        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(backgroundColor)
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }

  private var displayName: String {
    isSelected ? ratio.effectiveDisplayName(isPortrait: isPortrait) : ratio.displayName
  }

  private var backgroundColor: Color {
    if isSelected {
      return Color.accentColor.opacity(0.2)
    } else if isHovering {
      return Color.primary.opacity(0.1)
    }
    return Color.clear
  }
}

// MARK: - Crop Fill Color Button

struct CropFillColorButton: View {
  @Binding var selectedColor: Color
  @ObservedObject private var paletteStore = AnnotateColorPaletteStore.shared
  @State private var showsPopover = false
  @State private var draftCustomColor = Color.white

  private let presetColors: [Color] = [
    .clear, .white, .black, .gray, .red, .orange, .yellow, .green, .blue, .purple
  ]

  private let columns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5)

  var body: some View {
    Button {
      showsPopover.toggle()
    } label: {
      HStack(spacing: 5) {
        AnnotateColorSwatchCircle(
          color: selectedColor,
          isSelected: false,
          size: 14
        )
        Text(L10n.Common.fill)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.primary)
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(Color.secondary)
      }
      .padding(.horizontal, 8)
      .frame(height: 28)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.primary.opacity(0.08))
      )
    }
    .buttonStyle(.plain)
    .help(L10n.Common.fill)
    .popover(isPresented: $showsPopover, arrowEdge: .top) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(L10n.Common.fill)
          .font(Typography.labelMedium)
          .foregroundColor(SidebarColors.labelSecondary)

        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
          ForEach(presetColors, id: \.self) { color in
            Button {
              selectedColor = color
            } label: {
              AnnotateColorSwatchCircle(
                color: color,
                isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
                size: 22
              )
            }
            .buttonStyle(.plain)
            .help(AnnotateColorPaletteStore.isClear(color) ? L10n.Common.none : L10n.Common.fill)
          }

          ForEach(paletteStore.customColors, id: \.self) { color in
            AnnotateColorSwatchButton(
              color: color,
              isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
              size: 22,
              onDelete: {
                paletteStore.removeColor(color)
              }
            ) {
              selectedColor = color
            }
          }

          AnnotateCustomColorPickerControl(
            selectedColor: $selectedColor,
            draftColor: $draftCustomColor,
            swatchSize: 22
          )
        }

        Divider()

        AnnotateColorOpacitySlider(selectedColor: $selectedColor)
      }
      .padding(12)
      .frame(width: 196, alignment: .leading)
    }
  }
}
