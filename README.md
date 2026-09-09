# Show Me The Money

[소개 페이지](https://dlgudrms.github.io/showmethemoney/) · [앱 다운로드](https://github.com/dlgudrms/showmethemoney/releases/tag/v1.1.0-beta.1) · [개발자 후원](https://buymeacoffee.com/hglee)

무료 베타입니다. Mac은 Apple Silicon용이며 배포용 공증 전입니다. Windows는 x64/ARM64 빌드이며 실제 Windows 기기 UI 검증 전입니다.

**아이콘 클릭 → 주식 검색 → 선택 → 현재가 표시.** 한 종목의 가격만 보는 네이티브 앱입니다.

최종 앱은 `macos/`와 `windows/` 소스만 사용합니다. Electron, 브라우저 엔진, Node.js, 외부 패키지를 사용하지 않습니다. 이전 Electron 초안은 `archive/electron-prototype/`에 보존하며 네이티브 빌드에는 포함되지 않습니다.

## Mac

Swift + AppKit 메뉴 막대 앱입니다. 선택한 종목과 현재가가 상단에 표시됩니다. Dock 아이콘이나 메인 창은 없습니다.

```sh
bash macos/build.sh
open "dist/Show Me The Money.app"
```

빌드에는 Xcode Command Line Tools가 필요합니다. 실행에는 별도 런타임 설치가 필요 없습니다. 현재 Mac의 CPU 아키텍처로 빌드됩니다. 배포용 공증은 하지 않았습니다.

## Windows

C# + Windows Forms입니다. 트레이 아이콘을 클릭하여 종목을 검색합니다. 선택하면 작업표시줄 바로 위의 작은 가격창과 트레이 툴팁에 가격이 표시됩니다. 가격창을 클릭하면 다시 검색합니다. 작업표시줄 내부에 긴 가격 텍스트를 삽입하는 방식은 아닙니다. 트레이 우클릭 메뉴에서 종료합니다.

```powershell
dotnet publish windows/ShowMeTheMoney.csproj -c Release -r win-x64 --self-contained false -o dist/windows
```

.NET 10 SDK로 빌드하고 .NET 10 Desktop Runtime에서 실행합니다. 프레임워크 종속 빌드로 앱에 런타임을 포함하지 않습니다. 런타임까지 포함하려면 `--self-contained true`로 빌드할 수 있지만 용량이 커집니다.

## 사용

- `삼성전자`, `엔비디아`, `AAPL` 등으로 검색합니다. 자주 쓰는 한국어 이름 14개는 내장 검색, 나머지는 온라인 검색을 사용합니다. 모든 한국어 종목명이 검색되는 것은 아니며 실패 시 코드를 입력하세요.
- 국내 코스피는 `005930` 또는 `005930.KS`, 코스닥은 `086520.KQ`처럼 입력합니다.
- 한 종목만 저장합니다. Mac은 국내 종목을 네이버 KRX 시세로 7초마다, 해외 종목을 Yahoo 시세로 15초마다 조회합니다. Windows도 같은 제공처와 주기로 조회합니다. 검색은 입력 후 350ms 대기하여 요청 횟수를 줄입니다.
- Mac 메뉴 막대나 Windows 가격창/트레이 아이콘을 클릭한 뒤 **가격에 추가 표시**에서 `종목 코드`를 체크하거나 해제할 수 있습니다. 해제하면 가격만 표시합니다. 메뉴 막대에는 아이콘을 표시하지 않습니다. 즉시 반영되며 다음 실행에도 유지됩니다. 가격만 표시해도 마우스를 올리면 종목명과 코드를 확인할 수 있습니다.
- 창 하단에서 **한국어 / English**를 선택할 수 있습니다. 첫 실행은 시스템 언어를 따르고, 직접 선택한 언어는 저장됩니다. 언어 변경 시 평단·수량 입력과 보유 정보는 유지되며 화면·툴팁·오류 안내에 즉시 반영됩니다. 내장 종목은 한국어·영어 이름 모두 검색할 수 있습니다. 외부 제공처의 종목명은 원문으로 표시될 수 있습니다.
- **내 보유**에 평균 매수가와 보유 수량을 입력해 저장한 뒤 **평가총액 + 수익률로 표시**를 체크하면 현재가 대신 보유 평가금액과 수익률을 표시합니다. 체크할 때도 입력값을 저장합니다. 체크를 해제하면 현재가 표시로 돌아갑니다. 평단·수량·체크 상태는 종목마다 따로 저장합니다. 소수점 수량을 지원하며, 금액은 해당 종목 통화 기준입니다. 평가금액 = 현재가 × 수량, 수익률 = (현재가 − 평단) ÷ 평단 × 100. 수수료·세금·배당·환율 변동은 반영하지 않습니다.
- 가격의 시세 기준 시각은 툴팁에서 확인합니다. 실패하면 마지막 가격에 `⚠`를 붙입니다. 최초 실패는 `—`입니다.
- 아이콘을 클릭해 다른 종목을 선택하거나 종료할 수 있습니다.

국내 종목은 네이버의 공개 시세 응답에서 KRX 현재가와 시세 시각을 가져옵니다. NXT 가격과 섞지 않으며, 정규장 밖에서는 마지막 KRX 시세를 표시합니다. 실패할 때 지연된 Yahoo 데이터로 몰래 전환하지 않고 경고를 표시합니다. 7초 간격의 조회 방식으로 모든 체결을 스트리밍하는 방식은 아닙니다.

해외 종목은 Yahoo Finance의 비공식 공개 API를 사용하며 시세가 지연될 수 있습니다. 두 제공처 모두 요청 제한·서비스 변경 가능성이 있습니다. 거래 기능과 계정 로그인은 없습니다.

## 검증

후원 버튼은 `macos/Info.plist`의 `DonationURL`에 제작자의 HTTPS 후원 페이지 주소를 넣고 빌드하면 활성화됩니다. Windows는 실행 파일 옆 `donation.json`의 `url`에 같은 HTTPS 후원 주소를 넣습니다. 주소가 없는 동안은 비활성화되어 있으며, 임의의 결제 페이지로 연결하지 않습니다. 앱 안에서 결제나 계정 정보 입력을 받지 않고 기본 브라우저로 후원 페이지를 엽니다.

```sh
"dist/Show Me The Money.app/Contents/MacOS/ShowMeTheMoney" --self-test
"dist/Show Me The Money.app/Contents/MacOS/ShowMeTheMoney" --smoke-test
```

Windows의 실제 트레이/가격창 배치는 Windows 환경에서 확인해야 합니다.

Windows 코어 검증: `dotnet run --project windows-tests/CoreTests.csproj -c Release`. `-- --live`를 추가하면 국내 실제 시세도 확인합니다. 실행 안내는 `windows/TESTING.txt`를 참고하세요.

현재 개발자 후원 링크: https://buymeacoffee.com/hglee (Mac 및 Windows에 설정됨).

## 소스 구성

- `macos/`: Swift/AppKit 앱 전체 소스
- `windows/`, `windows-tests/`: C#/WinForms 앱 및 코어 검증
- `docs/`: GitHub Pages 정적 소개 페이지
- `web-source/`: React 소개 페이지 원본 (npm ci, npm run dev)
- `archive/electron-prototype/`: 이전 Electron 초안

설치 의존성, 빌드 캐시, 개인 설정은 포함하지 않습니다.
