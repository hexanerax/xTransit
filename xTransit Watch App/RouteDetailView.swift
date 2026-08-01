//
//  RouteDetailView.swift
//  xTransit Watch App
//
//  Created by Shubhankar Singh on 7/17/26.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State var steps: [RouteStep]
    let destination: String
    
    let radius: CGFloat = 80
    let startAngle: Double = 135
    let totalSweep: Double = 270
    let strokeWidth: CGFloat = 30
    let minGapDegrees: Double = 27
    let yOffset: CGFloat = 15
    let labelAngleOffset: Double = 2
    
    let dotSize: CGFloat = 6
    let dotSpacing: CGFloat = 10
    let dotColor: Color = Color(hex: "2C7CF6")
    
    @State var activeStepIndex: Int = 0
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var walkPolylineCoords: [CLLocationCoordinate2D] = []
    @State private var distanceToNext: String = "--"
    @State private var timeToNext: String = "--"
    @State private var showStopDetail: Bool = false
    
    @State private var showFullMap: Bool = false
    
    private let locationManager = LocationManager()
    private let updateTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    struct RouteStep {
        let label: String
        let minutes: Int
        let fill: String
        let border: String
        let badge: Badge
        var walkCoordinates: [CLLocationCoordinate2D] = []
        var boardingCoordinate: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid
        var trainDirection: String = ""
        var platformDirection: String = ""
        var trainStops: Int = 0
        var trainExitStop: String = ""
        var fare: String = ""
        var departureNumbers: String = "3, 5"
        var transferFromLine: String = ""
        var transferToLine: String = ""
        var busStops: Int = 0
        var busLine: String = ""
        var busStop: String = ""
        var busNumbers: String = ""
        
        enum Badge {
            case walk
            case transfer
            case train(line: String, color: String)
            case bus(color: String)
            case ferry(color: String)
        }
    }
    
    var isWalkActive: Bool {
        guard steps.indices.contains(activeStepIndex) else { return false }
        if case .walk = steps[activeStepIndex].badge { return true }
        return false
    }

    var isTransferActive: Bool {
        guard steps.indices.contains(activeStepIndex) else { return false }
        if case .transfer = steps[activeStepIndex].badge { return true }
        return false
    }
    
    var isTrainActive: Bool {
        guard steps.indices.contains(activeStepIndex) else { return false }
        if case .train = steps[activeStepIndex].badge { return true }
        return false
    }
    
    var isBusActive: Bool {
        guard steps.indices.contains(activeStepIndex) else { return false }
        if case .bus = steps[activeStepIndex].badge { return true }
        return false
    }
    
    var activeStep: RouteStep? {
        guard steps.indices.contains(activeStepIndex) else { return nil }
        return steps[activeStepIndex]
    }
    
    var activeWalkCoordinates: [CLLocationCoordinate2D] {
        guard steps.indices.contains(activeStepIndex) else { return [] }
        return steps[activeStepIndex].walkCoordinates
    }
    
    var nextStepDestination: CLLocationCoordinate2D? {
        activeWalkCoordinates.last
    }
    
    var arcAngles: [(start: Double, sweep: Double)] {
        let count = steps.count
        guard count > 0 else { return [] }
        let totalGap = minGapDegrees * Double(count - 1)
        let availableSweep = totalSweep - totalGap
        let totalMinutes = Double(steps.reduce(0) { $0 + $1.minutes })
        var result: [(start: Double, sweep: Double)] = []
        var current = startAngle
        var allocated = 0.0
        for (i, step) in steps.enumerated() {
            let sweep: Double
            if i == steps.count - 1 {
                sweep = availableSweep - allocated
            } else {
                sweep = (availableSweep * Double(step.minutes) / totalMinutes).rounded(.toNearestOrAwayFromZero)
                allocated += sweep
            }
            result.append((start: current, sweep: sweep))
            current += sweep + (i < count - 1 ? minGapDegrees : 0)
        }
        return result
    }
    
    func center(_ geo: GeometryProxy) -> CGPoint {
        CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + yOffset)
    }
    
    func point(_ geo: GeometryProxy, angle: Double, r: CGFloat) -> CGPoint {
        let rad = angle * .pi / 180
        return CGPoint(
            x: center(geo).x + r * cos(rad),
            y: center(geo).y + r * sin(rad)
        )
    }
    
    func badgeCircleColor(for step: RouteStep) -> Color {
        switch step.badge {
        case .walk: return Color(hex: "666666")
        case .transfer: return Color(hex: "1A1A1A")
        case .train(_, let color): return Color(hex: color)
        case .bus(let color): return Color(hex: color)
        case .ferry(let color): return Color(hex: color)
        }
    }
    
    var mapDiameter: CGFloat {
        (radius - strokeWidth / 2 - 4) * 2
    }
    
    var centerDiameter: CGFloat { mapDiameter }
    
    // MARK: - Real-time ETAs

    @MainActor func refreshETAs() async {
        for i in steps.indices {
            switch steps[i].badge {
            case .train(let line, _):
                let deps = await MTAService.subwayDepartures(line: line, boardingCoordinate: steps[i].boardingCoordinate)
                steps[i].departureNumbers = deps
            case .bus:
                let coord = steps[i].boardingCoordinate
                let busLine = steps[i].busLine
                if !busLine.isEmpty && CLLocationCoordinate2DIsValid(coord) {
                    steps[i].busNumbers = await MTAService.busDepartures(
                        route: busLine, stopCoordinate: coord
                    )
                }
            default:
                break
            }
        }
    }

    // MARK: - Walking Route

    func fetchWalkRoute() {
        walkPolylineCoords = []
        guard let start = activeWalkCoordinates.first,
              let end = activeWalkCoordinates.last else { return }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .walking
        
        MKDirections(request: request).calculate { response, _ in
            guard let polyline = response?.routes.first?.polyline else { return }
            let count = polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
            DispatchQueue.main.async {
                walkPolylineCoords = coords
                centerOnWalk()
            }
        }
    }
    
    func centerOnWalk() {
        let coords = walkPolylineCoords.isEmpty ? activeWalkCoordinates : walkPolylineCoords
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.003),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.4, 0.003)
        )
        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            mapPosition = .userLocation(fallback: .region(MKCoordinateRegion(center: center, span: span)))
        }
    }
    
    // MARK: - Realtime Distance + ETA
    
    func updateWalkingStats() {
        guard let userLocation = locationManager.manager.location,
              let dest = nextStepDestination else { return }

        let destLocation = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        let meters = userLocation.distance(from: destLocation)

        let formatter = MeasurementFormatter()
        formatter.unitStyle = .medium
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1

        let usesMetric = Locale.current.measurementSystem == .metric
        if usesMetric {
            if meters < 1000 {
                let m = Measurement(value: meters, unit: UnitLength.meters)
                distanceToNext = formatter.string(from: m)
            } else {
                let km = Measurement(value: meters / 1000, unit: UnitLength.kilometers)
                distanceToNext = formatter.string(from: km)
            }
        } else {
            let feet = meters * 3.28084
            if feet < 1000 {
                let ft = Measurement(value: feet, unit: UnitLength.feet)
                formatter.numberFormatter.maximumFractionDigits = 0
                distanceToNext = formatter.string(from: ft)
            } else {
                let miles = Measurement(value: meters / 1609.34, unit: UnitLength.miles)
                formatter.numberFormatter.maximumFractionDigits = 1
                distanceToNext = formatter.string(from: miles)
            }
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = .walking

        MKDirections(request: request).calculate { response, _ in
            DispatchQueue.main.async {
                if let travelTime = response?.routes.first?.expectedTravelTime {
                    let mins = Int(travelTime / 60)
                    self.timeToNext = mins <= 1 ? "1 min" : "\(mins) min"
                }
            }
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let c = center(geo)
            ZStack {
                Color.black.ignoresSafeArea()
                
                // MARK: - Walk Map
                if isWalkActive {
                    Map(position: $mapPosition) {
                        UserAnnotation()
                        if !walkPolylineCoords.isEmpty {
                            MapPolyline(coordinates: walkPolylineCoords)
                                .stroke(
                                    dotColor,
                                    style: StrokeStyle(
                                        lineWidth: dotSize,
                                        lineCap: .round,
                                        dash: [0, dotSpacing]
                                    )
                                )
                        }
                    }
                    .onTapGesture {
                        showFullMap = true
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    //.allowsHitTesting(false)
                    .frame(width: mapDiameter, height: mapDiameter)
                    .clipShape(Circle())
                    .position(c)
                    .onAppear {
                        fetchWalkRoute()
                        updateWalkingStats()
                    }
                    .onChange(of: activeStepIndex) { _, _ in
                        if isWalkActive {
                            fetchWalkRoute()
                            updateWalkingStats()
                        }
                    }
                    .onReceive(updateTimer) { _ in
                        if isWalkActive { updateWalkingStats() }
                    }
                }
                
                // MARK: - Train Center Info
                if isTrainActive, let step = activeStep {
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: centerDiameter, height: centerDiameter)
                        
                        if showStopDetail {
                            VStack(spacing: 0) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    Text("\(step.trainStops)")
                                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("STOPS")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(hex: "FFFFFF"))
                                        .padding(.bottom, 5)
                                }
                                Text(step.trainExitStop)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 4)
                            }
                            .padding(42)
                        } else {
                            // Direction view
                            VStack(spacing: 4) {
                                Text(step.platformDirection)
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                            }
                            .padding(42)
                        }
                    }
                    .position(c)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showStopDetail.toggle()
                        }
                    }
                }
                
                // MARK: - Bus Center Info
                if isBusActive, let step = activeStep {
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: centerDiameter, height: centerDiameter)
                        
                        VStack(spacing: 0) {
                            HStack(alignment: .bottom, spacing: 2) {
                                Text("\(step.busStops)")
                                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("STOPS")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.bottom, 5)
                            }
                            Text(step.busLine)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }
                        .padding(42)
                    }
                    .position(c)
                }
                
                // MARK: - Transfer Center Info
                if isTransferActive, let step = activeStep {
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: centerDiameter, height: centerDiameter)
                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: LineColors.badge(for: step.transferFromLine)))
                                    Text(step.transferFromLine)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(LineColors.textColor(for: step.transferFromLine) ? .black : .white)
                                        .offset(y: -1)
                                }
                                .frame(width: 36, height: 36)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(hex: "666666"))
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: LineColors.badge(for: step.transferToLine)))
                                    Text(step.transferToLine)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(LineColors.textColor(for: step.transferToLine) ? .black : .white)
                                        .offset(y: -1)
                                }
                                .frame(width: 36, height: 36)
                            }
                            Text("Transfer")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hex: "666666"))
                        }
                        .padding(42)
                    }
                    .position(c)
                }

                // MARK: - Arcs

                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    let angles = arcAngles[index]
                    let isActive = index == activeStepIndex
                    let showLabel = angles.sweep > 20
                    
                    Path { path in
                        path.addArc(center: c, radius: radius, startAngle: .degrees(angles.start), endAngle: .degrees(angles.start + angles.sweep), clockwise: false)
                    }
                    .stroke(
                        isActive ? Color(hex: step.border) : Color.black,
                        style: StrokeStyle(lineWidth: strokeWidth + 4, lineCap: .round)
                    )
                    
                    Path { path in
                        path.addArc(center: c, radius: radius, startAngle: .degrees(angles.start), endAngle: .degrees(angles.start + angles.sweep), clockwise: false)
                    }
                    .stroke(
                        Color(hex: step.fill),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    
                    Text(step.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "CCCCCC"))
                        .position(point(geo, angle: angles.start + labelAngleOffset, r: radius))
                        .opacity(showLabel ? 1 : 0)
                    
                    ZStack {
                        Circle().fill(badgeCircleColor(for: step))
                        if case .transfer = step.badge, isActive {
                            Circle().stroke(Color(hex: step.border), lineWidth: 2)
                        }
                        badgeIcon(for: step.badge)
                    }
                    .frame(width: 24, height: 24)
                    .position(point(geo, angle: angles.start + angles.sweep, r: radius))
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeStepIndex = index
                            showStopDetail = false
                        }
                    }
                }
                
                // MARK: - Walk Info Bar
                if isWalkActive {
                    VStack {
                        Spacer()
                        HStack(spacing: -70) {
                            HStack(spacing: 2) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.filled.curvepath")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: "666666"))
                                Text(distanceToNext)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                            
                            HStack(spacing: 2) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: "666666"))
                                Text(timeToNext)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                }
                
                // MARK: - Train Info Bar
                if isTrainActive, let step = activeStep {
                    VStack {
                        Spacer()
                        VStack(spacing: 0) {
                            Text(step.fare)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hex: "FFFFFF"))
                            HStack(spacing: 2) {
                                Image(systemName: "dot.radiowaves.up.forward")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.green)
                                Text("IN")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(hex: "888888"))
                                Text(step.departureNumbers)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("MIN")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(hex: "888888"))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                }
                
                // MARK: - Bus Info Bar
                if isBusActive, let step = activeStep {
                    VStack {
                        Spacer()
                        VStack(spacing: 0) {
                            Text(step.busStop)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            HStack(spacing: 2) {
                                Image(systemName: "dot.radiowaves.up.forward")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.green)
                                Text("IN")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(hex: "888888"))
                                Text(step.busNumbers)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("MIN")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(hex: "888888"))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                }
            }
        }
        .task { await refreshETAs() }
        .onReceive(updateTimer) { _ in Task { await refreshETAs() } }
        .navigationTitle(destination)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showFullMap) {
            FullMapView(walkCoordinates: activeWalkCoordinates, polylineCoords: walkPolylineCoords, dotColor: dotColor, dotSize: dotSize, dotSpacing: dotSpacing)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                }
            }
        }
    }
    
    @ViewBuilder
    func badgeIcon(for badge: RouteStep.Badge) -> some View {
        switch badge {
        case .walk:
            Image(systemName: "figure.walk")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
        case .transfer:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
        case .train(let line, _):
            Text(line)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LineColors.textColor(for: line) ? .black : .white)
                .offset(y: -1)
        case .bus:
            Image(systemName: "bus.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
        case .ferry:
            Image(systemName: "ferry.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    NavigationStack {
        RouteDetailView(steps: [
            RouteDetailView.RouteStep(
                label: "5", minutes: 5, fill: "1A1A1A", border: "666666", badge: .walk,
                walkCoordinates: [
                    CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0061),
                    CLLocationCoordinate2D(latitude: 40.7143, longitude: -74.0089),
                ]
            ),
            RouteDetailView.RouteStep(
                label: "13", minutes: 13,
                fill: LineColors.fill(for: "A"),
                border: LineColors.badge(for: "A"),
                badge: .train(line: "A", color: LineColors.badge(for: "A")),
                trainDirection: "Inwood-207 St",
                platformDirection: "Uptown & The Bronx",
                trainStops: 4,
                trainExitStop: "34 St-Penn Station",
                fare: "$3.00",
            ),
            
            RouteDetailView.RouteStep(
                label: "2", minutes: 2, fill: "1A1A1A", border: "666666", badge: .walk,
                walkCoordinates: [
                    CLLocationCoordinate2D(latitude: 40.7520, longitude: -73.9934),
                    CLLocationCoordinate2D(latitude: 40.7513, longitude: -73.9926),
                ]
            ),
            RouteDetailView.RouteStep(
                label: "8", minutes: 8,
                fill: "0A1729",
                border: "1A59B2",
                badge: .bus(color: "1A59B2"),
                busStops: 8,
                busLine: "M15 - SBS",
                busStop: "Allen St",
                busNumbers: "2, 6"
            ),
            
        ], destination: "5 Penn Plaza")
    }
}
