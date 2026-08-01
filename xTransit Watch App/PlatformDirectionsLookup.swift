//
//  PlatformDirectionsLookup.swift
//  xTransit Watch App
//

import Foundation

final class PlatformDirectionsLookup {
    static let shared = PlatformDirectionsLookup()

    // routeID → (GTFS headsign → platform label)
    private var table: [String: [String: String]] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "PlatformDirections", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return
        }
        table = decoded
    }

    /// Returns the platform-facing direction label for a route and trip headsign.
    /// - Parameters:
    ///   - routeID: GTFS route_id (e.g. "A", "1", "L")
    ///   - headsign: The trip headsign from the Google Directions response (e.g. "Canarsie-Rockaway Pkwy")
    func platformDirection(routeID: String, headsign: String) -> String? {
        guard let entries = table[routeID] else { return nil }
        let q = headsign.lowercased()
        // Exact match first
        if let label = entries.first(where: { $0.key.lowercased() == q })?.value {
            return label
        }
        // Prefix fallback — handles minor truncations in Google's headsign text
        return entries.first(where: {
            let k = $0.key.lowercased()
            return k.hasPrefix(q) || q.hasPrefix(k)
        })?.value
    }
}
