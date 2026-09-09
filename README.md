# Show Me The Money

작업하다가 주가 하나만 슬쩍 보고 싶어서 만들었습니다.
Mac은 상단 메뉴바에, Windows는 작업표시줄 위 작은 창에 가격을 띄워줍니다. 무료입니다.

[다운로드](https://github.com/dlgudrms/showmethemoney/releases/tag/v1.1.1-beta.2) · [소개 페이지](https://dlgudrms.github.io/showmethemoney/) · [커피 한 잔 사주기](https://buymeacoffee.com/hglee)

## 사용하기

압축을 풀고 앱을 실행한 뒤, 종목을 검색해서 고르면 됩니다.
`삼성전자`, `AAPL`, `005930`, `086520`처럼 이름이나 코드로 검색할 수 있습니다.

- 가격만 볼 수도 있고, 종목 코드를 같이 표시할 수도 있습니다.
- 평단과 수량을 넣으면 평가금액과 수익률로 바꿔 볼 수 있습니다.
- 한국어와 영어를 지원합니다.

Mac은 macOS 13 이상에서 Intel·Apple Silicon 모두 사용할 수 있습니다.
Windows는 PC에 맞는 x64 또는 ARM64 파일을 받으세요. [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/en-us/download/dotnet/10.0)이 필요합니다.

국내 시세는 네이버 KRX, 해외 시세는 Yahoo를 사용합니다. 장중에는 각각 7초·15초마다 확인하고, 장 종료 시에는 간격을 늘립니다. 시세가 지연될 수 있으며, 수익률에는 수수료와 세금이 포함되지 않습니다.

## 직접 빌드하기

Mac은 Swift/AppKit, Windows는 C#/WinForms로 만들었습니다.

```sh
# Mac — Xcode Command Line Tools 필요
bash macos/build.sh
```

```powershell
# Windows — .NET 10 SDK 필요
dotnet publish windows/ShowMeTheMoney.csproj -c Release -r win-x64 --self-contained false -o dist/windows
```

소개 페이지는 `docs/`, 이전 Electron 초안은 `archive/electron-prototype/`에 있습니다.
불편한 점이나 버그는 [Issues](https://github.com/dlgudrms/showmethemoney/issues)에 남겨주세요.
