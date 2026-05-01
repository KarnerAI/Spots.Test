//
//  ListPickerSheet.swift
//  Spots.Test
//
//  Single source of truth for presenting ListPickerView. Renders as a custom
//  bottom-anchored overlay (not a native .sheet) so the picker stays flush to
//  the screen edges on iOS 26, where Liquid Glass styling renders system sheets
//  as inset floating cards regardless of presentation modifiers.
//

import SwiftUI
import UIKit

struct ListPickerSheetModifier: ViewModifier {
    @Binding var spot: PlaceAutocompleteResult?
    @EnvironmentObject var locationSavingVM: LocationSavingViewModel
    var onSaveComplete: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0

    /// Hug content height so the Save button sits right under the rows.
    /// Drag handle (~17) + header (~62) + divider (1) + rows (60 each) + save bar (~74).
    private var contentHeight: CGFloat {
        let rowCount = max(locationSavingVM.userLists.count, 3)
        let dragHandle: CGFloat = 17
        let header: CGFloat = 62
        let divider: CGFloat = 1
        let rowsHeight = CGFloat(rowCount) * 60
        let saveBar: CGFloat = 74
        return dragHandle + header + divider + rowsHeight + saveBar
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content

            if spot != nil {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .transition(.opacity)
                    .zIndex(1)
            }

            if let spotData = spot {
                card(for: spotData)
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: spot != nil)
    }

    private func card(for spotData: PlaceAutocompleteResult) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ListPickerView(
                spotData: spotData,
                viewModel: locationSavingVM,
                onDismiss: { dismiss() },
                onSaveComplete: {
                    onSaveComplete?()
                    dismiss()
                }
            )
        }
        .frame(height: contentHeight)
        .background {
            Color.white
                .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
                .ignoresSafeArea(edges: .bottom)
        }
        .offset(y: dragOffset)
        .gesture(dragGesture)
        .accessibilityAddTraits(.isModal)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height > 100
                    || value.predictedEndTranslation.height > 200
                if shouldDismiss {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismiss() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        spot = nil
        dragOffset = 0
    }
}

extension View {
    func listPickerSheet(
        spot: Binding<PlaceAutocompleteResult?>,
        onSaveComplete: (() -> Void)? = nil
    ) -> some View {
        modifier(ListPickerSheetModifier(spot: spot, onSaveComplete: onSaveComplete))
    }

    /// Convenience overload for callers that hold a `NearbySpot?` instead of
    /// `PlaceAutocompleteResult?`. Bridges via `toPlaceAutocompleteResult()`.
    func listPickerSheet(
        spot: Binding<NearbySpot?>,
        onSaveComplete: (() -> Void)? = nil
    ) -> some View {
        let bridged = Binding<PlaceAutocompleteResult?>(
            get: { spot.wrappedValue?.toPlaceAutocompleteResult() },
            set: { if $0 == nil { spot.wrappedValue = nil } }
        )
        return modifier(ListPickerSheetModifier(spot: bridged, onSaveComplete: onSaveComplete))
    }
}
