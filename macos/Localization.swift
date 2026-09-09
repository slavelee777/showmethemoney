import Foundation

enum AppLanguage {
    static var code: String = {
        if let saved = UserDefaults.standard.string(forKey: "language"), ["ko", "en"].contains(saved) { return saved }
        return Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "ko" : "en"
    }()
    static var locale: Locale { Locale(identifier: code == "ko" ? "ko_KR" : "en_US") }
    static let english: [String: String] = [
        "종목을 검색하고 선택하세요": "Search and select a stock",
        "국내: 네이버 KRX 7초 · 해외: Yahoo 15초": "KRX: Naver 7s · Other: Yahoo 15s",
        "종목 코드": "Symbol", "평가총액 + 수익률로 표시": "Show holding value + return",
        "내 보유": "My holding", "평균 매수가": "Average cost",
        "평단과 수량 입력 후 저장 · 수수료·세금 제외": "Save cost and shares · Fees/taxes excluded",
        "저장": "Save", "주식 검색 · 클릭하여 종목 선택": "Click to search and select a stock",
        "종목명 또는 코드 검색": "Search name or symbol", "가격에 추가 표시": "Show with price",
        "보유 수량 (주)": "Shares", "예: 250000": "e.g. 250000", "예: 10": "e.g. 10",
        "평균 매수가, 종목 통화 기준": "Average cost in the stock's currency",
        "보유 수량, 주": "Number of shares", "종료": "Quit",
        "♡ 개발자 후원하기": "♡ Buy me a coffee",
        "후원 링크 준비 중": "Support link coming soon",
        "브라우저에서 개발자 후원 페이지 열기": "Open the developer's support page in your browser",
        "종목을 먼저 선택하세요": "Select a stock first",
        "평균 매수가 (원)": "Average cost (KRW)", "평균 매수가 (종목 통화)": "Cost (stock currency)",
        "평단·수량은 0보다 큰 숫자로 입력하세요 (소수 8자리까지)": "Enter positive cost and shares (up to 8 decimals)",
        "저장됨 · 종목 통화 기준 · 수수료·세금 제외": "Saved · Stock currency · Fees/taxes excluded",
        "주식": "Stocks", "평가 —": "Value —", "현재가": "Price", "시세 기준": "As of",
        "평가금액": "Value", "손익": "P/L", "수수료·세금 제외": "Fees/taxes excluded",
        "\n⚠ 조회 실패 · 마지막 성공 시세": "\n⚠ Update failed · Last available quote",
        "코드로 선택": "Use this symbol", "검색 중…": "Searching…",
        "검색 결과 없음 · 코스닥은 코드.KQ로 입력": "No results · For KOSDAQ, use code.KQ",
        "종목을 선택하면 상단에 현재가가 표시됩니다": "Select a stock to show its price in the menu bar",
        "온라인 검색 실패 · 종목 코드를 직접 입력할 수 있습니다": "Search unavailable · Enter a symbol directly",
        "시세 확인 중": "Fetching quote",
        "네이버 · KRX · 7초 갱신": "Naver · KRX · 7s",
        "Yahoo · 15초 갱신 · 지연 가능": "Yahoo · 15s · May be delayed",
        "조회 실패 · 표시된 가격은 마지막 성공 시세입니다": "Update failed · Showing the last available quote",
        "조회 실패 · 종목 코드와 인터넷 연결을 확인하세요": "Update failed · Check the symbol and connection",
        "네이버 · KRX": "Naver · KRX", "Yahoo · 지연 가능": "Yahoo · May be delayed",
        "장중": "Open", "장 마감/거래 대기": "Closed/waiting",
        "시세를 불러오지 못했습니다.": "Could not load the quote."
    ]
    static let stockNames: [String: String] = [
        "005930.KS": "Samsung Electronics", "000660.KS": "SK Hynix", "035420.KS": "NAVER",
        "035720.KS": "Kakao", "005380.KS": "Hyundai Motor", "373220.KS": "LG Energy Solution",
        "086520.KQ": "EcoPro", "247540.KQ": "EcoPro BM", "AAPL": "Apple", "NVDA": "NVIDIA",
        "TSLA": "Tesla", "MSFT": "Microsoft", "GOOGL": "Alphabet", "AMZN": "Amazon"
    ]
}

func L(_ korean: String) -> String { AppLanguage.code == "en" ? AppLanguage.english[korean] ?? korean : korean }
func quoteDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = AppLanguage.locale
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}
