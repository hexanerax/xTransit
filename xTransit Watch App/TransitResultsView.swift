//
//  TransitResultsView.swift
//  xTransit Watch App
//

import SwiftUI
import MapKit
import CoreLocation

struct TransitRoute: Identifiable, Hashable {
    let id = UUID()
    let duration: String
    let primaryLine: String
    let transfers: Int
    let modes: Set<String>
    let eta: String
    let fare: String
    let walkMinutes: Int
    let steps: [RouteDetailView.RouteStep]

    static func == (lhs: TransitRoute, rhs: TransitRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(duration: String, primaryLine: String, transfers: Int, modes: Set<String>,
         eta: String, fare: String, walkMinutes: Int, steps: [RouteDetailView.RouteStep]) {
        self.duration = duration
        self.primaryLine = primaryLine
        self.transfers = transfers
        self.modes = modes
        self.eta = eta
        self.fare = fare
        self.walkMinutes = walkMinutes
        self.steps = steps
    }
}

struct TransitResultsView: View {
    let destination: MKMapItem
    @State private var routes: [TransitRoute] = []
    @State private var isLoading: Bool = true
    @State private var filterOptions = TransitFilterOptions()
    @State private var showFilter: Bool = false
    @State private var selectedRoute: TransitRoute? = nil
    private let locationManager = LocationManager()

    var isFilterActive: Bool {
        !filterOptions.train || !filterOptions.bus || filterOptions.ferry
    }

    var filteredRoutes: [TransitRoute] {
        routes.filter { route in
            if route.modes.isEmpty { return true }
            if filterOptions.train && route.modes.contains("train") { return true }
            if filterOptions.bus && route.modes.contains("bus") { return true }
            if filterOptions.ferry && route.modes.contains("ferry") { return true }
            return false
        }
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Finding routes…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else if filteredRoutes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No routes match your filters")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(filteredRoutes) { transitRoute in
                            Button {
                                selectedRoute = transitRoute
                            } label: {
                                RouteCard(route: transitRoute)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .onAppear {
            Task { await fetchRoutes() }
        }
        .navigationDestination(item: $selectedRoute) { route in
            RouteDetailView(steps: route.steps, destination: destination.name ?? "Destination")
        }
        .sheet(isPresented: $showFilter) {
            FilterView(options: $filterOptions)
        }
        .navigationTitle(destination.name ?? "Directions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: isFilterActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private func fetchRoutes() async {
        guard let location = locationManager.manager.location else {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await fetchRoutes()
            return
        }

        routes = await GoogleDirectionsService.fetchRoutes(
            from: location.coordinate,
            to: destination.placemark.coordinate
        )
        isLoading = false

        for i in routes.indices {
            var steps = routes[i].steps
            var changed = false

            for j in steps.indices {
                switch steps[j].badge {
                case .train(let line, _):
                    steps[j].departureNumbers = await MTAService.subwayDepartures(
                        line: line, boardingCoordinate: steps[j].boardingCoordinate
                    )
                    changed = true
                case .bus:
                    let coord = steps[j].boardingCoordinate
                    let busLine = steps[j].busLine
                    if !busLine.isEmpty && CLLocationCoordinate2DIsValid(coord) {
                        steps[j].busNumbers = await MTAService.busDepartures(route: busLine, stopCoordinate: coord)
                        changed = true
                    }
                default:
                    break
                }
            }

            if changed {
                let r = routes[i]
                routes[i] = TransitRoute(
                    duration: r.duration, primaryLine: r.primaryLine,
                    transfers: r.transfers, modes: r.modes, eta: r.eta,
                    fare: r.fare, walkMinutes: r.walkMinutes, steps: steps
                )
            }
        }
    }
}

struct RouteCard: View {
    let route: TransitRoute

    var lineNames: [String] {
        let pattern = #"\b([1-7]|[ABCDEFGJLMNQRSWZ])\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let str = route.primaryLine
        let matches = regex.matches(in: str, range: NSRange(str.startIndex..., in: str))
        let found = matches.compactMap { Range($0.range, in: str).map { String(str[$0]) } }
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(route.duration)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            Text(route.primaryLine)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 2) {
                Text(route.eta)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(route.fare)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11))
                    Text("\(route.walkMinutes) min")
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.1), in: Capsule())

                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 8))

                ForEach(lineNames, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LineColors.textColor(for: line) ? .black : .white)
                        .frame(width: 22, height: 22)
                        .background(Color(hex: LineColors.badge(for: line)), in: Circle())
                }

                Spacer()

                if route.modes.contains("train") {
                    Image(systemName: "tram.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                } else if route.modes.contains("bus") {
                    Image(systemName: "bus.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                } else if route.modes.contains("ferry") {
                    Image(systemName: "ferry.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        TransitResultsView(destination: MKMapItem())
    }
}
