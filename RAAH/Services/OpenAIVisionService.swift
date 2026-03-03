import Foundation
import UIKit

/// Sends images to GPT-4o for visual analysis ("Snap and Ask")
final class OpenAIVisionService {
    
    struct VisionResponse {
        let description: String
        let confidence: String
    }
    
    func analyzeImage(_ image: UIImage, prompt: String = "What is this? Provide a concise, informative description suitable for a curious traveler. Include historical or cultural context if relevant.") async throws -> VisionResponse {
        guard APIKeys.isOpenAIConfigured else {
            throw VisionError.apiKeyMissing
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw VisionError.imageConversionFailed
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "system",
                    "content": "You are RAAH, an AI travel companion. When shown an image, identify what it is and provide fascinating context — historical, architectural, botanical, or cultural. Be concise but captivating, like an informed friend pointing something out. Keep responses under 100 words."
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                                "detail": "high"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 300
        ]
        
        let data = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(APIKeys.openAI)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        let (responseData, httpResponse) = try await URLSession.shared.data(for: request)
        
        guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw VisionError.requestFailed
        }
        
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw VisionError.invalidResponse
        }
        
        return VisionResponse(description: content, confidence: "high")
    }
    
    enum VisionError: LocalizedError {
        case apiKeyMissing
        case imageConversionFailed
        case requestFailed
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .apiKeyMissing: return "OpenAI API key not configured"
            case .imageConversionFailed: return "Could not process image"
            case .requestFailed: return "Vision request failed"
            case .invalidResponse: return "Could not parse response"
            }
        }
    }
}
