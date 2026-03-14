//
//  CurrencyFormatter.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import Foundation

final class CurrencyFormatter {
    static let shared = CurrencyFormatter()

    private let formatter: NumberFormatter

    private init() {
        formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.currencyCode = "CAD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
    }

    func format(_ amount: Decimal) -> String {
        formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) $"
    }
}
