//
//  PolylineDecoder.swift
//  xTransit Watch App
//

import CoreLocation

enum PolylineDecoder {
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var lat: Int = 0
        var lng: Int = 0

        while index < encoded.endIndex {
            var b: Int
            var shift = 0
            var result = 0

            repeat {
                guard index < encoded.endIndex else { return coords }
                b = Int(encoded[index].asciiValue ?? 63) - 63
                index = encoded.index(after: index)
                result |= (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20

            lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)

            shift = 0
            result = 0

            repeat {
                guard index < encoded.endIndex else { return coords }
                b = Int(encoded[index].asciiValue ?? 63) - 63
                index = encoded.index(after: index)
                result |= (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20

            lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)

            coords.append(CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            ))
        }

        return coords
    }
}
