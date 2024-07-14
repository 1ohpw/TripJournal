import Foundation

/// An object that can be used to create a new trip.
struct TripCreate: Codable {
    let name: String
    let startDate: Date
    let endDate: Date
    
    enum CodingKeys: String, CodingKey {
        case name
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

/// An object that can be used to update an existing trip.
struct TripUpdate: Codable {
    let name: String
    let startDate: Date
    let endDate: Date
    
    enum CodingKeys: String, CodingKey {
        case name
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

/// An object that can be used to create a media.
struct MediaCreate: Codable {
    let eventId: Event.ID
    let base64Data: Data
    
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case base64Data = "base64_data"
    }
}

/// An object that can be used to create a new event.
struct EventCreate: Codable {
    let tripId: Trip.ID
    let name: String
    let note: String?
    let date: Date
    let location: Location?
    let transitionFromPrevious: String?
    
    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case name, note, date, location
        case transitionFromPrevious = "transition_from_previous"
    }
}



/// An object that can be used to update an existing event.
struct EventUpdate: Codable {
    var name: String
    var note: String?
    var date: Date
    var location: Location?
    var transitionFromPrevious: String?
    
    enum CodingKeys: String, CodingKey {
        case name, note, date, location
        case transitionFromPrevious = "transition_from_previous"
    }
}
