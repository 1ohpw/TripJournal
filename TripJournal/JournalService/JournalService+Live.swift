import Combine
import Foundation

enum HTTPMethods: String {
    case POST = "POST"
}

enum MIMEType: String {
    case JSON = "application/json"
    case form = "application/x-www-form-urlencoded"
}

enum HTTPHeaders: String {
    case accept = "Accept"
    case contentType = "Content-Type"
}

enum NetworkError: Error {
    case badUrl
    case badResponse
    case failedToDecodeResponse
}

struct LoginRequest: Codable {
    let username: String
    let password: String
}

/// A live version of the `JournalService`.
class LiveJournalService: JournalService {
    var tokenExpired: Bool = false
    
    @Published private var token: Token? {
        didSet {
            if let token = token {
                try? KeychainHelper.shared.saveToken(token)
            } else {
                try? KeychainHelper.shared.deleteToken()
            }
        }
    }
    
    var isAuthenticated: AnyPublisher<Bool, Never> {
        $token
            .map { $0 != nil }
            .eraseToAnyPublisher()
    }
    
    private let urlSession: URLSession
    
    enum EndPoints {
        static let base = "http://localhost:8000/"
        
        case register
        case login
        case trips
        case trip(id: Int)
        case events
        case event(id: Int)
        case media
        case mediaItem(id: Int)
        
        private var stringValue: String {
            switch self {
            case .register:
                return EndPoints.base + "register"
            case .login:
                return EndPoints.base + "token"
            case .trips:
                return EndPoints.base + "trips"
            case .trip(let id):
                return EndPoints.base + "trips/\(id)"
            case .events:
                return EndPoints.base + "events"
            case .event(let id):
                return EndPoints.base + "events/\(id)"
            case .media:
                return EndPoints.base + "media"
            case .mediaItem(let id):
                return EndPoints.base + "media/\(id)"
            }
        }
        
        var url: URL? {
            return URL(string: stringValue)
        }
    }
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.urlSession = URLSession(configuration: configuration)
        
        if let savedToken = try? KeychainHelper.shared.getToken() {
            if !isTokenExpired(savedToken) {
                self.token = savedToken
            } else {
                self.tokenExpired = true
                self.token = nil
            }
        } else {
            self.token = nil
        }
    }
    
    func register(username: String, password: String) async throws -> Token {
        let request = try createRegisterRequest(username: username, password: password)
        return try await performNetworkRequest(request, responseType: Token.self)
    }
    
    func logIn(username: String, password: String) async throws -> Token {
        let request = try createLoginRequest(username: username, password: password)
        return try await performNetworkRequest(request, responseType: Token.self)
    }
    
    private func createRegisterRequest(username: String, password: String) throws -> URLRequest {
        guard let url = EndPoints.register.url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethods.POST.rawValue
        request.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        request.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)
        
        let registerRequest = LoginRequest(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(registerRequest)
        
        return request
    }
    
    private func createLoginRequest(username: String, password: String) throws -> URLRequest {
        guard let url = EndPoints.login.url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethods.POST.rawValue
        request.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        request.addValue(MIMEType.form.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)
        
        let loginData = "grant_type=&username=\(username)&password=\(password)"
        request.httpBody = loginData.data(using: .utf8)
        
        return request
    }
    
    private func performNetworkRequest<T: Decodable>(_ request: URLRequest, responseType: T.Type) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.badResponse
        }
        
        do {
            let decoder = JSONDecoder()
            
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
                
                dateFormatter.formatOptions = [.withInternetDateTime]
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
                
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
            }
            
            let object = try decoder.decode(T.self, from: data)
            if var token = object as? Token {
                token.expirationDate = Token.defaultExpirationDate()
                self.token = token
            }
            return object
        } catch {
            throw NetworkError.failedToDecodeResponse
        }
    }
    
    private func performVoidNetworkRequest(_ request: URLRequest) async throws {
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            throw NetworkError.badResponse
        }
    }
    
    func logOut() {
        token = nil
    }
    
    func checkIfTokenExpired() {
        if let currentToken = token,
           isTokenExpired(currentToken) {
            tokenExpired = true
            self.token = nil
        }
    }
    
    private func isTokenExpired(_ token: Token) -> Bool {
        guard let expirationDate = token.expirationDate else {
            return false
        }
        return expirationDate <= Date()
    }
    
    func createTrip(with tripCreate: TripCreate) async throws -> Trip {
        guard let url = EndPoints.trips.url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(tripCreate)
        request.httpBody = jsonData
        
        return try await performNetworkRequest(request, responseType: Trip.self)
    }
    
    func getTrips() async throws -> [Trip] {
        guard let url = EndPoints.trips.url else {
            throw NetworkError.badUrl
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        return try await performNetworkRequest(request, responseType: [Trip].self)
    }
    
    func getTrip(withId tripId: Trip.ID) async throws -> Trip {
        guard let url = EndPoints.trip(id: tripId).url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        return try await performNetworkRequest(request, responseType: Trip.self)
    }
    
    func updateTrip(withId tripId: Trip.ID, and tripUpdate: TripUpdate) async throws -> Trip {
        guard let url = EndPoints.trip(id: tripId).url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(tripUpdate)
        
        return try await performNetworkRequest(request, responseType: Trip.self)
    }
    
    func deleteTrip(withId tripId: Trip.ID) async throws {
        guard let url = EndPoints.trip(id: tripId).url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        try await performVoidNetworkRequest(request)
    }
    
    // MARK: - Event Methods
    
    func createEvent(with eventCreate: EventCreate) async throws -> Event {
        guard let url = EndPoints.events.url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        request.httpBody = try JSONEncoder().encode(eventCreate)
        
        return try await performNetworkRequest(request, responseType: Event.self)
    }
    
    func updateEvent(withId eventId: Event.ID, and eventUpdate: EventUpdate) async throws -> Event {
        guard let url = EndPoints.event(id: eventId).url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(eventUpdate)
        
        return try await performNetworkRequest(request, responseType: Event.self)
    }
    
    func deleteEvent(withId eventId: Event.ID) async throws {
        guard let url = EndPoints.event(id: eventId).url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        try await performVoidNetworkRequest(request)
    }
    
    // MARK: - Media Methods
    
    func createMedia(with mediaCreate: MediaCreate) async throws -> Media {
        guard let url = EndPoints.media.url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(mediaCreate)
        
        return try await performNetworkRequest(request, responseType: Media.self)
    }
    
    func deleteMedia(withId mediaId: Media.ID) async throws {
        guard let url = EndPoints.mediaItem(id: mediaId).url else {
            throw NetworkError.badUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        try await performVoidNetworkRequest(request)
    }
}

