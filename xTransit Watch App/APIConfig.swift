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
        func value(_ key: String) -> String {
            let v = dict[key] ?? ""
            return v == "PASTE_YOUR_KEYS_HERE" ? "" : v
        }
        googleMapsAPIKey = value("GoogleMapsAPIKey")
        mtaBusTimeAPIKey = value("MTABusTimeAPIKey")
        mtaSubwayAPIKey = value("MTASubwayAPIKey")
    }
}
