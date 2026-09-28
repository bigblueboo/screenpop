import CoreGraphics
import Foundation

public enum NamerError: LocalizedError, Equatable {
    case missingKey
    case api(String)
    case unusableReply

    public var errorDescription: String? {
        switch self {
        case .missingKey: "No OpenAI key. Add one in Settings to get names."
        case .api(let message): "OpenAI: \(message)"
        case .unusableReply: "OpenAI didn't return a usable name."
        }
    }
}

/// Asks an OpenAI vision model for a short descriptive filename.
public struct Namer: Sendable {
    public static let defaultModel = "gpt-6-luna"

    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String = Namer.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    static let instructions = """
        You name screenshot files. Reply with a filename for this image: 2 to 6 lowercase words \
        joined by hyphens, no extension, no dates. Be specific about what it shows: name the app, \
        product, object, or error when you can tell (e.g. "stripe-checkout-card-declined", \
        "red-macaw-portrait", "figma-pricing-table"). Never use the words screenshot, image, or picture.
        """

    public func name(for image: CGImage) async throws -> String {
        let jpeg = try ImageFile.thumbnailJPEG(image)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(model: model, jpeg: jpeg))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw NamerError.api(Self.errorMessage(in: data) ?? "HTTP \(status)")
        }
        guard let slug = FileNaming.slug(try Self.parseName(from: data)) else { throw NamerError.unusableReply }
        return slug
    }

    static func body(model: String, jpeg: Data) -> [String: Any] {
        [
            "model": model,
            "instructions": instructions,
            "input": [[
                "role": "user",
                "content": [[
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())",
                    "detail": "low",
                ]],
            ]],
            "reasoning": ["effort": "none"],
            "max_output_tokens": 60,
            "store": false,
            "text": ["format": [
                "type": "json_schema",
                "name": "filename",
                "strict": true,
                "schema": [
                    "type": "object",
                    "properties": ["name": ["type": "string"]],
                    "required": ["name"],
                    "additionalProperties": false,
                ],
            ]],
        ]
    }

    private struct Reply: Decodable {
        struct Item: Decodable {
            let type: String
            let content: [Content]?
        }
        struct Content: Decodable {
            let type: String
            let text: String?
        }
        let output: [Item]
    }

    private struct NamePayload: Decodable { let name: String }

    private struct ErrorReply: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }

    static func parseName(from data: Data) throws -> String {
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        let text = reply.output
            .filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
            .first { $0.type == "output_text" }?.text
        guard let text, let payload = try? JSONDecoder().decode(NamePayload.self, from: Data(text.utf8))
        else { throw NamerError.unusableReply }
        return payload.name
    }

    static func errorMessage(in data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorReply.self, from: data))?.error.message
    }
}
