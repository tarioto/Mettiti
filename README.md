# Mettiti

An iOS app that checks today's weather and tells you what to wear and what to bring — sunglasses, an umbrella, a heavier jacket — using Apple's on-device language model.

## Features

- **Outfit & packing recommendations** generated on-device with Apple Intelligence (Foundation Models framework). Nothing is sent to a cloud LLM.
- **Today's forecast** from [Open-Meteo](https://open-meteo.com) — high/low, precipitation chance, UV index, and wind. No API key required.
- **Hourly temperature chart** with an ensemble-forecast confidence band and a rain overlay.
- **Home screen widgets**
  - *Today's Emojis* (small) — a quick emoji glance
  - *Today's Summary* (small) — a short text summary
  - *Today's Full Plan* (medium / large / extra large) — weather, summary, and the full wear & bring list
- **Customizable home screen** — reorder or hide the Weather, Today's plan, and Wear & bring cards.
- **Settings** — current location or a searched custom location, Fahrenheit/Celsius, and background themes (Sunset, Ocean, Aurora, Midnight) with independent Light/Dark appearance.
- Pull-to-refresh and a refresh button.

## Requirements

- Xcode 26 or later
- iOS 26.0+ (iPhone)
- A device with Apple Intelligence enabled for AI recommendations. On unsupported devices or the simulator without Apple Intelligence, the app shows the weather and explains why recommendations are unavailable.

## Getting started

```sh
open Mettiti.xcodeproj
```

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you change `project.yml` or add files, regenerate it:

```sh
brew install xcodegen   # if you don't have it
xcodegen generate
```

### Building under your own Apple developer account

Signing is configured for the original author's team. To run on your own device, update these in `project.yml` and regenerate:

- `DEVELOPMENT_TEAM` — your team ID
- `bundleIdPrefix` and each `PRODUCT_BUNDLE_IDENTIFIER`
- `PROVISIONING_PROFILE_SPECIFIER` for both targets (or switch `CODE_SIGN_STYLE` to `Automatic` and remove them)
- The App Group `group.com.timarioto.Mettiti` in both `.entitlements` files — the app and widget extension share forecast data through it

### Secret scanning

Pushes and PRs are scanned for secrets with [gitleaks](https://github.com/gitleaks/gitleaks) in CI, and GitHub push protection rejects known token formats. To also catch secrets before they leave your machine, enable the local pre-push hook:

```sh
brew install gitleaks
git config core.hooksPath .githooks
```

## Project structure

```
Mettiti/
  Models/        Weather and recommendation models (shared with widgets)
  Services/      Open-Meteo clients, location, OutfitAdvisor, preference stores
  Shared/        Types shared between the app and widget extension
  Views/         SwiftUI screens and components
MettitiWidgets/  WidgetKit extension (emoji, summary, combined widgets)
project.yml        XcodeGen spec
```

## Credits

Weather data by [Open-Meteo.com](https://open-meteo.com/) (CC BY 4.0).

## License

MIT — see [LICENSE](LICENSE).
