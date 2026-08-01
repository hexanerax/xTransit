//
//  SearchView.swift
//  xTransit Watch App
//

import SwiftUI
import MapKit
import CoreLocation

struct SearchView: View {
    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var results: [MKMapItem] = []
    @State private var navigateToResults: Bool = false
    @State private var quickDest: MKMapItem? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    TextField("Search", text: $query)
                        .onSubmit { search() }

                    HStack(spacing: 8) {
                        QuickDestButton(label: "Home", icon: "house.fill", tint: .blue) {
                            quickDest = makeMapItem(
                                lat: 40.694986, lon: -73.982858, name: "Home"
                            )
                        }
                        QuickDestButton(label: "Work", icon: "briefcase.fill", tint: .orange) {
                            quickDest = makeMapItem(
                                lat: 40.751980, lon: -73.994087, name: "Work"
                            )
                        }
                    }

                    if isSearching {
                        ProgressView()
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToResults) {
                ResultsView(query: query, results: results)
            }
            .navigationDestination(item: $quickDest) { dest in
                TransitResultsView(destination: dest)
            }
        }
    }

    private func makeMapItem(lat: Double, lon: Double, name: String) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }

    private func search() {
        guard !query.isEmpty else { return }
        isSearching = true
        results = []

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest

        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                results = response?.mapItems ?? []
                isSearching = false
                if !results.isEmpty {
                    navigateToResults = true
                }
            }
        }
    }
}

struct QuickDestButton: View {
    let label: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(tint.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SearchView()
}
