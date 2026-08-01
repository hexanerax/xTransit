//
//  ResultsView.swift
//  xTransit Watch App
//
//  Created by Shubhankar Singh on 7/17/26.
//

import SwiftUI
import MapKit
import CoreLocation

extension MKMapItem: @retroactive Hashable {
    public static func == (lhs: MKMapItem, rhs: MKMapItem) -> Bool {
        lhs.placemark.coordinate.latitude == rhs.placemark.coordinate.latitude &&
        lhs.placemark.coordinate.longitude == rhs.placemark.coordinate.longitude &&
        lhs.name == rhs.name
    }
}

struct ResultsView: View {
    let query: String
    let results: [MKMapItem]
    
    @State private var selectedDestination: MKMapItem? = nil
    @State private var crownValue: Double = 0
    @State private var selectedIndex: Int = 0
    @State private var showMap: Bool = false
    @State private var userLocation: CLLocation? = nil
    private let locationManager = LocationManager()
    @Environment(\.dismiss) private var dismiss
    
    func distance(to item: MKMapItem) -> String? {
        guard let userLocation else { return nil }
        let dest = CLLocation(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
        let meters = userLocation.distance(from: dest)
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement) + " away"
    }
    
    var selectedItem: MKMapItem? {
        guard !results.isEmpty else { return nil }
        return results[selectedIndex]
    }
    
    var mapPosition: MapCameraPosition {
        guard let item = selectedItem else { return .automatic }
        return .item(item)
    }
    
    var body: some View {
        Group {
            if showMap {
                mapView
            } else {
                listView
            }
        }
        .onAppear {
            userLocation = locationManager.manager.location
        }
        .navigationDestination(item: $selectedDestination) { destination in
            TransitResultsView(destination: destination)
        }
        .navigationTitle(showMap ? (selectedItem?.name ?? query) : query)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMap.toggle()
                } label: {
                    Image(systemName: showMap ? "list.bullet" : "map")
                }
            }
        }
    }
    
    // MARK: - Map View
    
    var mapView: some View {
        let position: MapCameraPosition = mapPosition
        return ZStack(alignment: .bottom) {
            Map(position: .constant(position)) {
                mapMarkers
            }
            .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .including([.publicTransport])))
            .ignoresSafeArea()
            .mapControls { }
            .allowsHitTesting(false)
            
            resultCard
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: Double(max(results.count - 1, 0)),
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in
            let rounded = Int(newValue.rounded())
            if rounded != selectedIndex {
                selectedIndex = rounded
            }
        }
    }
    
    // MARK: - Markers
    
    @MapContentBuilder
    var mapMarkers: some MapContent {
        ForEach(Array(results.enumerated()), id: \.offset) { index, item in
            Marker(item.name ?? "", coordinate: item.placemark.coordinate)
                .tint(index == selectedIndex ? .blue : .gray)
        }
    }
    
    // MARK: - Result Card
    
    @ViewBuilder
    var resultCard: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedIndex + 1) of \(results.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(item.name ?? "Unknown")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let dist = distance(to: item) {
                    Text(dist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.black.opacity(0.5))
                    .blendMode(.softLight)
            )
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.2), lineWidth: 1).blendMode(.lighten))
            .padding(.horizontal, 4)
            .padding(.bottom, -12)
        }
    }
    
    // MARK: - List View
    
    var listView: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                    Button {
                        crownValue = Double(index)
                        selectedDestination = item
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Unknown")
                                .font(.system(size: 14, weight: .medium))
                            if let address = item.placemark.title {
                                Text(address)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

#Preview {
    ResultsView(query: "Coffee", results: [])
}
