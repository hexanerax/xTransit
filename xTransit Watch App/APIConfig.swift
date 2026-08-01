//
//  APIConfig.swift
//  xTransit Watch App
//

import Foundation

struct APIConfig {
    static let shared = APIConfig()

    let googleMapsAPIKey: String
    let mtaBusTimeAPIKey: String
    let mtaSubwayAPIKey: String

    private init() {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            googleMapsAPIKey = ""
            mtaBusTimeAPIKey = ""
            mtaSubwayAPIKey = ""
            return
        }
        googleMapsAPIKey = dict["GoogleMapsAPIKey"] ?? ""
        mtaBusTimeAPIKey = dict["MTABusTimeAPIKey"] ?? ""
        mtaSubwayAPIKey = dict["MTASubwayAPIKey"] ?? ""
    }
}
