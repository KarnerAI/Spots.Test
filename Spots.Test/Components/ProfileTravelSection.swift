//
//  ProfileTravelSection.swift
//  Spots.Test
//
//  Shared "Footprint" section used by both own-profile (ProfileView) and
//  other-user profile (UserProfileView). Renders the Countries/Cities picker
//  and tappable rows grouped from a supplied `[Spot]`. Default tab is Countries.
//

import SwiftUI

struct ProfileTravelSection<CityDestination: View, CountryDestination: View>: View {
    let spots: [Spot]
    let title: String
    @ViewBuilder let cityDestination: (CityRowData) -> CityDestination
    @ViewBuilder let countryDestination: (CountryRowData) -> CountryDestination

    /// Tag 0 = Countries (default); tag 1 = Cities.
    @State private var segment: Int = 0

    init(
        spots: [Spot],
        title: String = "Footprint",
        @ViewBuilder cityDestination: @escaping (CityRowData) -> CityDestination,
        @ViewBuilder countryDestination: @escaping (CountryRowData) -> CountryDestination
    ) {
        self.spots = spots
        self.title = title
        self.cityDestination = cityDestination
        self.countryDestination = countryDestination
    }

    private var cityRows: [CityRowData] { LocationGrouping.cityRows(from: spots) }
    private var countryRows: [CountryRowData] { LocationGrouping.countryRows(from: spots) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
                .padding(.horizontal, 20)

            Picker("Footprint View", selection: $segment) {
                Text("Countries").tag(0)
                Text("Cities").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            rowList
                .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var rowList: some View {
        let cities = cityRows
        let countries = countryRows

        if cities.isEmpty && countries.isEmpty {
            emptyState("Save spots to see your footprint.")
        } else if segment == 0 {
            if countries.isEmpty {
                emptyState("No countries yet — save spots with country info.")
            } else {
                rowGroup {
                    ForEach(Array(countries.enumerated()), id: \.element.id) { index, country in
                        NavigationLink(destination: countryDestination(country)) {
                            countryRow(country, isLast: index == countries.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            if cities.isEmpty {
                emptyState("No cities yet — save spots with city info.")
            } else {
                rowGroup {
                    ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                        NavigationLink(destination: cityDestination(city)) {
                            cityRow(city, isLast: index == cities.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func rowGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                    .stroke(Color.gray200, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundColor(.gray500)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
    }

    private func cityRow(_ city: CityRowData, isLast: Bool) -> some View {
        HStack {
            Text(city.name)
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))

            Spacer()

            Text("\(city.count) \(city.count == 1 ? "spot" : "spots")")
                .font(.system(size: 12))
                .foregroundColor(.gray500)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().background(Color.gray100)
            }
        }
    }

    private func countryRow(_ country: CountryRowData, isLast: Bool) -> some View {
        HStack {
            HStack(spacing: 12) {
                Group {
                    if let flag = country.flag {
                        Text(flag).font(.system(size: 22))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                            .foregroundColor(.gray500)
                            .frame(width: 24, height: 24)
                    }
                }
                .frame(width: 28, alignment: .center)

                Text(country.displayName)
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.063, green: 0.094, blue: 0.157))
            }

            Spacer()

            Text("\(country.count) \(country.count == 1 ? "spot" : "spots")")
                .font(.system(size: 12))
                .foregroundColor(.gray500)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().background(Color.gray100)
            }
        }
    }
}
