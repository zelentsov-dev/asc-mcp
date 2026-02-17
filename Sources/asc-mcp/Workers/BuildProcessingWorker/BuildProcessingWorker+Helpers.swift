import Foundation

// MARK: - Helper Methods
extension BuildProcessingWorker {
    
    func getStateDescription(_ state: String) -> String {
        switch state {
        case "PROCESSING":
            return "Build is currently being processed by App Store Connect"
        case "VALID":
            return "Build processing completed successfully and is ready for use"
        case "INVALID":
            return "Build validation failed - check for errors in the build"
        case "FAILED":
            return "Build processing failed - upload may need to be retried"
        default:
            return "Unknown processing state"
        }
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}