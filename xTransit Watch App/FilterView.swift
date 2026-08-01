//
//  FilterView.swift
//  xTransit Watch App
//
//  Created by Shubhankar Singh on 7/17/26.
//

import SwiftUI

struct TransitFilterOptions {
    var train: Bool = true
    var bus: Bool = true
    var ferry: Bool = false
}

struct FilterView: View {
    @Binding var options: TransitFilterOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Filter Routes")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                FilterToggleRow(
                    label: "Train",
                    icon: "tram.fill",
                    tint: .blue,
                    isOn: $options.train
                )

                FilterToggleRow(
                    label: "Bus",
                    icon: "bus.fill",
                    tint: .orange,
                    isOn: $options.bus
                )

                FilterToggleRow(
                    label: "Ferry",
                    icon: "ferry.fill",
                    tint: .teal,
                    isOn: $options.ferry
                )

                Button {
                    dismiss()
                } label: {
                    Text("Apply")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }
}

struct FilterToggleRow: View {
    let label: String
    let icon: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(tint)
                .labelsHidden()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    FilterView(options: .constant(TransitFilterOptions()))
}
