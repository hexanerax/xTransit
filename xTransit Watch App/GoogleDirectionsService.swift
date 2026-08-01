//
//  GoogleDirectionsService.swift
//  xTransit Watch App
//

import CoreLocation

private struct DirectionsResponse: Decodable {
    let status: String
    let routes: [GRoute]
}

private struct GRoute: Decodable {
    let legs: [GLeg]
    let fare: GFare?
}

private struct GFare: Decodable {
    let text: String
}

private struct GLeg: Decodable {
    let duration: GDuration
    let steps: [GStep]
}

private struct GDuration: Decodable {
    let value: Int
}

private struct GStep: Decodable {
    let travel_mode: String
    let duration: GDuration
    let polyline: GPolyline
    let transit_details: GTransitDetails?
}

private struct GPolyline: Decodable {
    let points: String
}

private struct GTransitDetails: Decodable {
    let line: GLine
    let headsign: String
    let num_stops: Int
    let departure_stop: GStop
    let arrival_stop: GStop
}

private struct GLine: Decodable {
    let short_name: String?
    let name: String?
    let vehicle: GVehicle
}

private struct GVehicle: Decodable {
    let type: String
}

private struct GStop: Decodable {
    let name: String
    let location: GLocation
}

private struct GLocation: Decodable {
    let lat: Double
    let lng: Double
}

enum GoogleDirectionsService {
    static func fetchRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> [TransitRoute] {
        let key = APIConfig.shared.googleMapsAPIKey
        guard !key.isEmpty, !key.hasPrefix("YOUR_") else { return [] }

        let urlString = "https://maps.googleapis.com/maps/api/directions/json"
            + "?origin=\(origin.latitude),\(origin.longitude)"
            + "&destination=\(destination.latitude),\(destination.longitude)"
            + "&mode=transit&alternatives=true&key=\(key)"

        guard let url = URL(string: urlString) else { return [] }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(DirectionsResponse.self, from: data),
              response.status == "OK" else { return [] }

        return response.routes.prefix(3).map { convertRoute($0) }
    }

    private static func convertRoute(_ route: GRoute) -> TransitRoute {
        guard let leg = route.legs.first else {
            return TransitRoute(duration: "--", primaryLine: "Route", transfers: 0,
                                modes: [], eta: "--", fare: "--", walkMinutes: 0, steps: [])
        }

        let totalSecs = leg.duration.value
        let totalMins = totalSecs / 60
        let fare = route.fare?.text ?? "$2.90"

        var steps: [RouteDetailView.RouteStep] = []
        var modes = Set<String>()
        var primaryLine = ""
        var transfers = -1
        var walkMinutes = 0

        for (i, gStep) in leg.steps.enumerated() {
            let stepMins = max(gStep.duration.value / 60, 1)

            switch gStep.travel_mode {
            case "WALKING":
                var fromLine: String? = nil
                var toLine: String? = nil
                if gStep.duration.value <= 180,
                   i > 0, i < leg.steps.count - 1,
                   leg.steps[i - 1].travel_mode == "TRANSIT",
                   leg.steps[i + 1].travel_mode == "TRANSIT",
                   let prev = leg.steps[i - 1].transit_details,
                   let next = leg.steps[i + 1].transit_details {
                    let dLat = prev.arrival_stop.location.lat - next.departure_stop.location.lat
                    let dLon = prev.arrival_stop.location.lng - next.departure_stop.location.lng
                    if dLat * dLat + dLon * dLon < 3.24e-6 {  // ≈ 200 m
                        fromLine = routeId(from: prev.line.short_name ?? "", fallbackName: prev.line.name ?? "")
                        toLine   = routeId(from: next.line.short_name ?? "", fallbackName: next.line.name ?? "")
                    }
                }

                if let from = fromLine, let to = toLine {
                    var s = RouteDetailView.RouteStep(label: "", minutes: 0, fill: "1A1A1A", border: "666666", badge: .transfer)
                    s.transferFromLine = from
                    s.transferToLine   = to
                    steps.append(s)
                } else {
                    steps.append(RouteDetailView.RouteStep(
                        label: "\(stepMins)", minutes: stepMins,
                        fill: "1A1A1A", border: "666666",
                        badge: .walk, walkCoordinates: PolylineDecoder.decode(gStep.polyline.points)
                    ))
                    walkMinutes += stepMins
                }

            case "TRANSIT":
                guard let td = gStep.transit_details else { break }
                let vtype = td.line.vehicle.type
                let shortName = routeId(from: td.line.short_name ?? "", fallbackName: td.line.name ?? "")
                let lowerName = (td.line.name ?? "").lowercased()
                let lineType = lowerName.contains("express") ? "express"
                    : lowerName.contains("local") ? "local"
                    : lowerName.contains("shuttle") ? "shuttle"
                    : "train"
                transfers += 1

                switch vtype {
                case "SUBWAY", "HEAVY_RAIL", "COMMUTER_TRAIN":
                    modes.insert("train")
                    if primaryLine.isEmpty { primaryLine = "\(shortName) \(lineType) toward \(td.headsign)" }
                    var s = RouteDetailView.RouteStep(
                        label: "\(stepMins)", minutes: stepMins,
                        fill: LineColors.fill(for: shortName),
                        border: LineColors.badge(for: shortName),
                        badge: .train(line: shortName, color: LineColors.badge(for: shortName))
                    )
                    s.trainDirection = td.headsign
                    s.trainStops = td.num_stops
                    s.trainExitStop = td.arrival_stop.name
                    s.fare = fare
                    s.departureNumbers = "--"
                    s.boardingCoordinate = CLLocationCoordinate2D(
                        latitude: td.departure_stop.location.lat,
                        longitude: td.departure_stop.location.lng
                    )
                    s.platformDirection = PlatformDirectionsLookup.shared.platformDirection(
                        routeID: shortName, headsign: td.headsign
                    ) ?? td.headsign
                    steps.append(s)

                case "BUS", "INTERCITY_BUS", "TROLLEYBUS":
                    modes.insert("bus")
                    if primaryLine.isEmpty { primaryLine = "\(shortName) bus toward \(td.headsign)" }
                    var s = RouteDetailView.RouteStep(
                        label: "\(stepMins)", minutes: stepMins,
                        fill: "0A1729", border: "1A59B2",
                        badge: .bus(color: "1A59B2")
                    )
                    s.busStops = td.num_stops
                    s.busLine = shortName
                    s.busStop = td.departure_stop.name
                    s.busNumbers = "--"
                    s.boardingCoordinate = CLLocationCoordinate2D(
                        latitude: td.departure_stop.location.lat,
                        longitude: td.departure_stop.location.lng
                    )
                    steps.append(s)

                case "FERRY":
                    modes.insert("ferry")
                    if primaryLine.isEmpty { primaryLine = "\(shortName) toward \(td.headsign)" }
                    steps.append(RouteDetailView.RouteStep(
                        label: "\(stepMins)", minutes: stepMins,
                        fill: "0A1A1A", border: "0A9BA6",
                        badge: .ferry(color: "0A9BA6")
                    ))

                default: break
                }

            default: break
            }
        }

        let durationStr = totalMins < 60
            ? "\(totalMins) min"
            : "\(totalMins / 60)h \(totalMins % 60)m"
        let etaDate = Date().addingTimeInterval(TimeInterval(totalSecs))
        let fmt = DateFormatter()
        fmt.timeStyle = .short

        return TransitRoute(
            duration: durationStr,
            primaryLine: primaryLine.isEmpty ? "Transit route" : primaryLine,
            transfers: max(transfers, 0),
            modes: modes,
            eta: fmt.string(from: etaDate) + " ETA",
            fare: fare,
            walkMinutes: walkMinutes,
            steps: steps
        )
    }

    // Strips "C Line" → "C"; handles Google's occasional verbose short_name.
    private static func routeId(from shortName: String, fallbackName: String) -> String {
        let source = shortName.isEmpty ? fallbackName : shortName
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        let withoutLine = trimmed.lowercased().hasSuffix(" line")
            ? String(trimmed.dropLast(5)).trimmingCharacters(in: .whitespaces)
            : trimmed
        if withoutLine.count <= 6 { return withoutLine.uppercased() }
        let first = withoutLine.split(separator: " ").first.map(String.init) ?? withoutLine
        return (first.count <= 3 ? first : withoutLine).uppercased()
    }
}
