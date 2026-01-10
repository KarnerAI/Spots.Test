//
//  ShareViewController.swift
//  ShareExtension
//
//  Created for Share Extension feature
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController, NSExtensionRequestHandling {
    
    private let contentProcessor = ShareContentProcessor.shared
    private let placeExtractionService = PlaceExtractionService.shared
    private let locationSavingService = LocationSavingService.shared
    
    private var hostingController: UIHostingController<ShareConfirmationView>?
    
    func beginRequest(with context: NSExtensionContext) {
        guard let extensionItems = context.inputItems as? [NSExtensionItem] else {
            context.cancelRequest(withError: NSError(domain: "ShareExtension", code: -1, userInfo: [NSLocalizedDescriptionKey: "No items to share"]))
            return
        }
        
        Task { @MainActor in
            await processExtensionItems(extensionItems, context: context)
        }
    }
    
    @MainActor
    private func processExtensionItems(_ extensionItems: [NSExtensionItem], context: NSExtensionContext) async {
        // Show loading view
        let loadingView = UIHostingController(rootView: LoadingView())
        addChild(loadingView)
        view.addSubview(loadingView.view)
        loadingView.view.frame = view.bounds
        loadingView.didMove(toParent: self)
        
        do {
            // Extract content
            let (text, images) = try await contentProcessor.processExtensionItems(extensionItems)
            
            // Check if we have any content
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
                showError("No content found to process. Please share text, images, or URLs.")
                return
            }
            
            // Extract places
            let places = try await placeExtractionService.extractPlaces(
                fromText: text,
                images: images,
                userLocation: nil // Could get from LocationManager if needed
            )
            
            // Remove loading view
            loadingView.willMove(toParent: nil)
            loadingView.view.removeFromSuperview()
            loadingView.removeFromParent()
            
            // Show confirmation view
            if places.isEmpty {
                showEmptyState()
            } else {
                showConfirmationView(places: places, context: context)
            }
            
        } catch {
            print("Error processing share: \(error)")
            showError("Failed to process shared content: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func showConfirmationView(places: [PlaceAutocompleteResult], context: NSExtensionContext) {
        let confirmationView = ShareConfirmationView(
            places: places,
            onSave: { placesToSave, selectedPlaceIds in
                return try await self.savePlaces(places: placesToSave, selectedPlaceIds: selectedPlaceIds, context: context)
            },
            onCancel: {
                context.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"]))
            }
        )
        
        let hostingController = UIHostingController(rootView: confirmationView)
        self.hostingController = hostingController
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.didMove(toParent: self)
    }
    
    @MainActor
    private func showEmptyState() {
        let emptyView = UIHostingController(rootView: EmptyStateView())
        addChild(emptyView)
        view.addSubview(emptyView.view)
        emptyView.view.frame = view.bounds
        emptyView.didMove(toParent: self)
    }
    
    @MainActor
    private func showError(_ message: String) {
        let errorView = UIHostingController(rootView: ErrorView(message: message))
        addChild(errorView)
        view.addSubview(errorView.view)
        errorView.view.frame = view.bounds
        errorView.didMove(toParent: self)
    }
    
    private func savePlaces(places: [PlaceAutocompleteResult], selectedPlaceIds: Set<String>, context: NSExtensionContext) async throws -> Int {
        let savedCount = try await locationSavingService.savePlacesToBucketlist(
            places: places,
            selectedPlaceIds: selectedPlaceIds
        )
        
        if savedCount > 0 {
            // Complete the extension request
            context.completeRequest(returningItems: nil, completionHandler: nil)
        }
        
        return savedCount
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Analyzing content...")
                .font(.system(size: 16))
                .foregroundColor(.gray600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray400)
            
            Text("No places found")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.gray500)
            
            Text("We couldn't find any places in the shared content")
                .font(.system(size: 15))
                .foregroundColor(.gray400)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.gray900)
            
            Text(message)
                .font(.system(size: 15))
                .foregroundColor(.gray600)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

