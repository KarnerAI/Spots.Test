//
//  DebugLogger.swift
//  Spots.Test
//

import Foundation

enum DebugLogger {
    private static let logPath: String = {
        // Get the project root directory dynamically
        let fileManager = FileManager.default
        if let projectRoot = fileManager.currentDirectoryPath.components(separatedBy: "/Spots.Test").first {
            return projectRoot + "/Spots.Test/.cursor/debug.log"
        }
        // Fallback to a temporary directory if project root can't be determined
        return fileManager.temporaryDirectory.appendingPathComponent("spots-debug.log").path
    }()
    private static let serverEndpoint = "http://127.0.0.1:7242/ingest/4011b5a8-bf93-4d06-83bf-44b26380aefc"
    
    static func log(
        sessionId: String = "debug-session",
        runId: String,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        let payload: [String: Any] = [
            "sessionId": sessionId,
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        
        let url = URL(fileURLWithPath: logPath)
        let line = json + Data([0x0A])
        
        if FileManager.default.fileExists(atPath: logPath),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
        
        #if DEBUG
        if let serverURL = URL(string: serverEndpoint) {
            var request = URLRequest(url: serverURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
            URLSession.shared.dataTask(with: request).resume()
        }
        #endif
    }
}
