import Foundation

enum PriceDisplayMode: String {
    case price, daily, holding
    static func resolve(_ raw: String?, legacyTotal: Bool) -> Self {
        raw.flatMap(Self.init(rawValue:)) ?? (legacyTotal ? .holding : .price)
    }
}

struct Holding: Codable {
    let averageCost: Decimal
    let shares: Decimal
    var showTotal: Bool

    static func positiveNumber(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard value.range(of: "^[0-9]{1,12}(\\.[0-9]{1,8})?$", options: .regularExpression) != nil,
              let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), number > 0 else { return nil }
        return number
    }

    var isValid: Bool { averageCost >= Decimal(string: "0.00000001")! && shares >= Decimal(string: "0.00000001")! && averageCost <= 999_999_999_999 && shares <= 999_999_999_999 }

    func valuation(price: Double) -> (total: Decimal, profit: Decimal, percent: Decimal)? {
        guard isValid, price.isFinite, price > 0, price <= 999_999_999_999, let current = Decimal(string: String(price)) else { return nil }
        let cost = averageCost * shares
        let total = current * shares
        return (total, total - cost, (current - averageCost) / averageCost * 100)
    }
}

func holdingMoney(_ amount: Decimal, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.locale = AppLanguage.locale
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = currency == "KRW" ? 0 : 2
    formatter.maximumFractionDigits = currency == "KRW" ? 0 : 2
    let prefix = currency == "KRW" ? "₩" : currency == "USD" ? "$" : currency + " "
    return prefix + (formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—")
}

func holdingPercent(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let value = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—"
    return (amount > 0 ? "+" : "") + value + "%"
}
