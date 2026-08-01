//
//  FullMapView.swift
//  xTransit Watch App
//
//  Created by Shubhankar Singh on 7/26/26.
//

import SwiftUI
import MapKit

struct FullMapView: View {
    let walkCoordinates: [CLLocationCoordinate2D]
    let polylineCoords: [CLLocationCoordinate2D]
    let dotColor: Color
    let dotSize: CGFloat
    let dotSpacing: CGFloat

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            if !polylineCoords.isEmpty {
                MapPolyline(coordinates: polylineCoords)
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
        .mapStyle(.standard(pointsOfInterest: .including([.publicTransport])))
        .ignoresSafeArea()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                }
            }
        }
    }
}
