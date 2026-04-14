//
//  ShareContentProcessor.swift
//  Spots.Test
//
//  Created for Share Extension feature
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import Vision

/// Processes shared content from iOS share sheet
class ShareContentProcessor {
    static let shared = ShareContentProcessor()
    
    private init() {}
    
    /// Process extension items and extract all text content
    /// - Parameter extensionItems: Items from NSExtensionContext
    /// - Returns: Tuple containing extracted text and images
    func processExtensionItems(_ extensionItems: [NSExtensionItem]) async throws -> (text: String, images: [UIImage]) {
        var extractedText: [String] = []
        var extractedImages: [UIImage] = []
        
        for item in extensionItems {
            // Extract text from attachments
            if let text = item.attributedContentText?.string, !text.isEmpty {
                extractedText.append(text)
            }
            
            // Process attachments
            guard let attachments = item.attachments else { continue }
            
            for attachment in attachments {
                // Handle images
                if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let image = try? await loadImage(from: attachment) {
                        extractedImages.append(image)
                        // Try OCR on image
                        if let ocrText = try? await extractTextFromImage(image) {
                            extractedText.append(ocrText)
                        }
                    }
                }
                
                // Handle URLs
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        extractedText.append(url.absoluteString)
                        // Try to fetch webpage content
                        if let webpageText = try? await fetchWebpageContent(url: url) {
                            extractedText.append(webpageText)
                        }
                    }
                }
                
                // Handle plain text
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        extractedText.append(text)
                    }
                }
                
                // Handle text (attributed string)
                if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.text.identifier) as? String {
                        extractedText.append(text)
                    }
                }
            }
        }
        
        let combinedText = extractedText.joined(separator: "\n\n")
        return (combinedText, extractedImages)
    }
    
    // MARK: - Private Helpers
    
    private func loadImage(from attachment: NSItemProvider) async throws -> UIImage? {
        return try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let image = item as? UIImage {
                    continuation.resume(returning: image)
                } else if let url = item as? URL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else if let data = item as? Data, let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func extractTextFromImage(_ image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            return ""
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                continuation.resume(returning: recognizedStrings.joined(separator: " "))
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
    
    private func fetchWebpageContent(url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Try to extract text from HTML (simple approach)
        if let htmlString = String(data: data, encoding: .utf8) {
            // Simple HTML tag removal (basic implementation)
            let text = htmlString
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Limit length to avoid token limits
            return String(text.prefix(5000))
        }
        
        return ""
    }
}

