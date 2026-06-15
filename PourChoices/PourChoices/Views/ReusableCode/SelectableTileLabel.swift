//
//  SelectableTileLabel.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/14/26.
//

import SwiftUI


struct SelectableTileLabel: View {
    let assetName: String
    let label: String
    let isSelected: Bool
    var showCheckmark: Bool = false
    var showBorder: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .scaleEffect(1.4)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? Color.black : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.accent : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(showBorder && isSelected ? Color.accent : Color.clear, lineWidth: 2)
            )

            if showCheckmark && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.accent)
                    .background(Circle().fill(Color(.systemGroupedBackground)).padding(2))
                    .offset(x: 6, y: -6)
            }
        }
    }
}
