//
//  MTAService.swift
//  xTransit Watch App
//

import CoreLocation
import Foundation

// MARK: - Subway (GTFS-RT, no key required)

enum MTAService {
    static func subwayDepartures(line: String, boardingCoordinate: CLLocationCoordinate2D) async -> String {
        guard let url = URL(string: subwayFeedURL(for: line)) else { return "--" }
        var request = URLRequest(url: url)
        let apiKey = APIConfig.shared.mtaSubwayAPIKey
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return "--"
        }

        var reader = GTFSRTReader(data: data)
        // Parse all (stopId, departureTime) pairs from the feed for this route.
        let pairs = reader.parseDeparturePairs(routeId: line.uppercased())

        // If we have a boarding coordinate, find the stop_id from the feed itself that is
        // closest to that coordinate — not globally nearest, so we don't pick a different
        // line's platform at the same station complex.
        let stopId: String?
        if CLLocationCoordinate2DIsValid(boardingCoordinate) {
            let uniqueStops = Set(pairs.map(\.stopId))
            stopId = SubwayStops.nearest(
                lat: boardingCoordinate.latitude,
                lon: boardingCoordinate.longitude,
                among: uniqueStops
            )
        } else {
            stopId = nil
        }

        let times: [Int64]
        if let stopId {
            times = pairs.compactMap { $0.stopId == stopId ? $0.time : nil }
        } else {
            times = pairs.map(\.time)
        }
        return formatMinutes(from: times)
    }

    // MARK: Bus (BusTime SIRI, requires MTABusTimeAPIKey in Config.plist)

    static func busDepartures(route: String, stopCoordinate: CLLocationCoordinate2D) async -> String {
        let key = APIConfig.shared.mtaBusTimeAPIKey
        guard !key.isEmpty else { return "--" }
        guard CLLocationCoordinate2DIsValid(stopCoordinate) else { return "--" }

        guard let stopRef = await busStopRef(
            near: stopCoordinate,
            route: route,
            key: key
        ) else { return "--" }

        let lineRef = "MTA%20NYCT_\(route.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? route)"
        let urlStr = "https://bustime.mta.info/api/siri/stop-monitoring.json"
            + "?key=\(key)"
            + "&MonitoringRef=\(stopRef)"
            + "&LineRef=\(lineRef)"
            + "&maximumStopVisits=3"

        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "--"
        }

        let visits = busMonitoringVisits(from: json)
        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let minutes: [Int] = visits.compactMap { visit in
            guard let arrivalStr = visit["ExpectedArrivalTime"] as? String
                    ?? visit["AimedArrivalTime"] as? String,
                  let arrivalDate = fmt.date(from: arrivalStr) else { return nil }
            let mins = Int(arrivalDate.timeIntervalSince(now) / 60)
            return mins >= 0 ? mins : nil
        }

        if minutes.isEmpty { return "--" }
        return minutes.prefix(3).map { "\($0)" }.joined(separator: ", ")
    }

    // MARK: - Private helpers

    private static func subwayFeedURL(for line: String) -> String {
        let base = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs"
        switch line.uppercased() {
        case "A", "C", "E": return base + "-ace"
        case "B", "D", "F", "M": return base + "-bdfm"
        case "G": return base + "-g"
        case "J", "Z": return base + "-jz"
        case "L": return base + "-l"
        case "N", "Q", "R", "W": return base + "-nqrw"
        case "SIR": return base + "-si"
        default: return base  // 1-7, S
        }
    }

    private static func formatMinutes(from times: [Int64]) -> String {
        let now = Int64(Date().timeIntervalSince1970)
        let mins = times.sorted()
            .compactMap { t -> Int? in
                let secs = t - now
                guard secs > 0 else { return nil }
                return Int((secs + 59) / 60)  // ceiling: 43s → 1 min, not 0
            }
            .filter { $0 <= 90 }
        guard !mins.isEmpty else { return "--" }
        return mins.prefix(2).map { "\($0)" }.joined(separator: ", ")
    }

    private static func busStopRef(
        near coord: CLLocationCoordinate2D,
        route: String,
        key: String
    ) async -> String? {
        let lineRef = "MTA%20NYCT_\(route.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? route)"
        let urlStr = "https://bustime.mta.info/api/siri/stops-for-location.json"
            + "?key=\(key)"
            + "&lat=\(coord.latitude)"
            + "&lon=\(coord.longitude)"
            + "&latSpan=0.005&lonSpan=0.005"
            + "&NutsCode=\(lineRef)"

        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let stops = busStopPoints(from: json)
        return stops.first?["StopPointRef"] as? String
    }

    private static func busStopPoints(from json: [String: Any]) -> [[String: Any]] {
        let siri = json["Siri"] as? [String: Any]
        let delivery = siri?["ServiceDelivery"] as? [String: Any]
        let pointsDelivery = delivery?["StopPointsDelivery"] as? [String: Any]
        return pointsDelivery?["AnnotatedStopPointRef"] as? [[String: Any]] ?? []
    }

    private static func busMonitoringVisits(from json: [String: Any]) -> [[String: Any]] {
        let siri = json["Siri"] as? [String: Any]
        let serviceDelivery = siri?["ServiceDelivery"] as? [String: Any]
        let deliveries = serviceDelivery?["StopMonitoringDelivery"] as? [[String: Any]] ?? []

        return deliveries.flatMap { delivery in
            let visits = delivery["MonitoredStopVisit"] as? [[String: Any]] ?? []
            return visits.compactMap { visit in
                let journey = visit["MonitoredVehicleJourney"] as? [String: Any]
                return journey?["MonitoredCall"] as? [String: Any]
            }
        }
    }
}

// MARK: - Minimal GTFS-RT protobuf reader

// Parses only the fields needed: FeedEntity→TripUpdate→(TripDescriptor.route_id,
// StopTimeUpdate→StopTimeEvent.time). All other fields are skipped.
struct GTFSRTReader {
    private var data: Data
    private var pos: Int = 0

    init(data: Data) {
        self.data = data
    }

    // Returns all future (stopId, departureTime) pairs for the given route.
    // The caller picks the relevant stop from this list using coordinate proximity.
    mutating func parseDeparturePairs(routeId: String) -> [(stopId: String, time: Int64)] {
        var result: [(stopId: String, time: Int64)] = []
        let now = Int64(Date().timeIntervalSince1970)
        let target = routeId.uppercased()

        while pos < data.count {
            guard let (field, wire) = readTag() else { break }
            if field == 2, wire == 2, let entityData = readLD() {
                var er = GTFSRTReader(data: entityData)
                result.append(contentsOf: er.parseEntity(routeId: target, now: now))
            } else {
                skip(wire: wire)
            }
        }
        return result
    }

    // MARK: FeedEntity

    private mutating func parseEntity(routeId: String, now: Int64) -> [(stopId: String, time: Int64)] {
        var tuData: Data?
        while pos < data.count {
            guard let (field, wire) = readTag() else { break }
            if field == 3, wire == 2 { tuData = readLD() }
            else { skip(wire: wire) }
        }
        guard let d = tuData else { return [] }
        var r = GTFSRTReader(data: d)
        return r.parseTripUpdate(routeId: routeId, now: now)
    }

    // MARK: TripUpdate

    private mutating func parseTripUpdate(routeId: String, now: Int64) -> [(stopId: String, time: Int64)] {
        var tripData: Data?
        var stuList: [Data] = []

        while pos < data.count {
            guard let (field, wire) = readTag() else { break }
            switch (field, wire) {
            case (1, 2): tripData = readLD()
            case (2, 2): if let d = readLD() { stuList.append(d) }  // MTA uses field 2, not the standard field 3
            default: skip(wire: wire)
            }
        }

        guard let td = tripData else { return [] }
        var tr = GTFSRTReader(data: td)
        guard tr.tripRouteId() == routeId else { return [] }

        return stuList.compactMap { stuData -> (stopId: String, time: Int64)? in
            var sr = GTFSRTReader(data: stuData)
            return sr.stuPair(now: now)
        }
    }

    // MARK: TripDescriptor → route_id (field 5)

    private mutating func tripRouteId() -> String? {
        while pos < data.count {
            guard let (field, wire) = readTag() else { break }
            if field == 5, wire == 2, let d = readLD() {
                return String(data: d, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
            }
            skip(wire: wire)
        }
        return nil
    }

    // MARK: StopTimeUpdate → (stopId, time), or nil if no future time exists.

    private mutating func stuPair(now: Int64) -> (stopId: String, time: Int64)? {
        var depData: Data?
        var arrData: Data?
        var stopId: String?
        while pos < data.count {
            guard let (field, wire) = readTag() else { break }
            switch (field, wire) {
            case (3, 2): depData = readLD()
            case (2, 2): arrData = readLD()
            case (4, 2):
                if let d = readLD() {
                    stopId = String(data: d, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            default: skip(wire: wire)
            }
        }
        guard let stopId else { return nil }
        let d = depData ?? arrData
        guard let d else { return nil }
        var dr = GTFSRTReader(data: d)
        guard let t = dr.steTime(), t > now else { return nil }
        return (stopId, t)
    }

    // MARK: StopTimeEvent → time (field 2, varint int64)

    private mutating func steTime() -> Int64? {
        while pos < data.count {
            guard let (field, wire) = readTag() else { break }
            if field == 2, wire == 0, let v = readVarint() {
                return Int64(bitPattern: v)
            }
            skip(wire: wire)
        }
        return nil
    }

    // MARK: Low-level binary readers

    private mutating func readTag() -> (UInt32, UInt64)? {
        guard let v = readVarint() else { return nil }
        return (UInt32(v >> 3), v & 0x7)
    }

    private mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while pos < data.count {
            let byte = UInt64(data[pos]); pos += 1
            result |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    // Returns a fresh 0-based Data copy so sub-readers always start at index 0.
    private mutating func readLD() -> Data? {
        guard let len = readVarint(), len < 10_000_000 else { return nil }
        let end = pos + Int(len)
        guard end <= data.count else { return nil }
        let slice = Data(data[pos..<end])
        pos = end
        return slice
    }

    private mutating func skip(wire: UInt64) {
        switch wire {
        case 0: _ = readVarint()
        case 1: pos = min(pos + 8, data.count)
        case 2: _ = readLD()
        case 5: pos = min(pos + 4, data.count)
        default: pos = data.count
        }
    }
}
