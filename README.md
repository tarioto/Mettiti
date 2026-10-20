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
- **Customizable main screen** — reorder or hide the Weather, Today's plan, and Wear & bring cards. On wider displays, like iPhone Duo open or a large iPhone in landscape, the cards sit side by side.
- **Settings** — current location or a searched custom location, Fahrenheit/Celsius, and background themes (Sunset, Ocean, Aurora, Midnight) with independent Light/Dark appearance.
- A Plan Window menu on the main screen for how far ahead the outfit covers, and pull-to-refresh.

## Requirements

- Xcode 27.1 or later
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

### Releasing

Every build goes to TestFlight first; an App Store release is a TestFlight build you promote.

1. Set `MARKETING_VERSION` in `project.yml` to the version you're working toward, as `MAJOR.MINOR.PATCH` (e.g. `1.1.0`), and regenerate.
2. Upload builds to TestFlight as often as you like:

   ```sh
   scripts/testflight.sh              # archive and upload
   scripts/testflight.sh --no-upload  # archive only
   ```

   Build numbers count up from 1. Xcode assigns the next one at upload time by asking App Store Connect, so there's nothing to bump or commit. Uploading uses the Apple account signed in to Xcode.
3. In App Store Connect, pick the build for that version and submit it for review.
4. Once the version is released, App Store Connect accepts no more builds for it — bump `MARKETING_VERSION` before the next upload.

Merging to `main` also runs `scripts/testflight.sh` in CI (`.github/workflows/testflight.yml`), so TestFlight follows `main`. CI signs in with an App Store Connect API key (App Store Connect → Users and Access → Integrations, **Admin** role so Xcode can manage signing) stored as these repository secrets:

- `ASC_KEY_P8` — the contents of the downloaded `AuthKey_XXXXXXXXXX.p8`
- `ASC_KEY_ID` — the key ID
- `ASC_ISSUER_ID` — the issuer ID shown above the keys list

Without `ASC_KEY_P8`, the workflow skips the upload with a warning. It can also be run by hand from the Actions tab.

TestFlight and App Store installs run the same binary. The app tells them apart at runtime (that's how TestFlight installs get `AppIcon-Beta`), so any other TestFlight-only behavior has to be decided the same way.

### Secret scanning

Pushes and PRs are scanned for secrets with [gitleaks](https://github.com/gitleaks/gitleaks) in CI, and GitHub push protection rejects known token formats. To also catch secrets before they leave your machine, enable the local pre-push hook:

```sh
brew install gitleaks
git config core.hooksPath .githooks
```

### CI

Workflow actions in `.github/workflows/` are pinned to full commit SHAs with a `# vX.Y.Z` version comment, and Dependabot opens weekly PRs to update them.

## Project structure

```
Mettiti/
  Models/        App-only models and UI config (recommendation state, themes, cards)
  Services/      Weather clients, location, OutfitAdvisor, DayPlanFetcher, background refresh
  Persistence/   Preference stores
  Features/
    DayPlan/     Day plan screen, its view model and components
    Settings/    Settings screen
  Shared/        Models and types compiled into both the app and widget extension
MettitiWidgets/  WidgetKit extension (emoji, summary, combined widgets)
project.yml        XcodeGen spec
```

## Credits

Weather data by [Open-Meteo.com](https://open-meteo.com/) (CC BY 4.0).

## License

MIT — see [LICENSE](LICENSE).
