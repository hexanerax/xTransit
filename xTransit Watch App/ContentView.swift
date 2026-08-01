//
//  ContentView.swift
//  xTransit Watch App
//
//  Created by Shubhankar Singh on 7/17/26.
//

import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isCentered: Bool = true
    @State private var showSearch: Bool = false
    private let locationManager = LocationManager()

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()
            }
            .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .including([.publicTransport])))
            .ignoresSafeArea()
            .navigationTitle("xTransit")
            .navigationBarTitleDisplayMode(.inline)
            .onMapCameraChange { _ in
                isCentered = false
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button {
                            withAnimation {
                                position = .userLocation(fallback: .automatic)
                                isCentered = true
                            }
                        } label: {
                            Image(systemName: isCentered ? "location.fill" : "location")
                        }

                        Spacer()

                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }
        }
    }
}

class LocationManager: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}

#Preview {
    ContentView()
}
