# Mettiti

A weather-driven outfit suggestion app for iOS, with home screen widgets.

## Language

### Appearance

**Theme**:
The colour scheme of the app's home screen background, chosen in Settings. One of Default, Sunset, Ocean, Aurora or Midnight.
_Avoid_: Skin, colour scheme

**Appearance**:
Whether the app runs in Light mode, Dark mode or follows the System setting. Separate from the **Theme**.
_Avoid_: Mode, theme

### App icons

**Install Source**:
Where the running copy of the app came from: an Xcode (dev) build, TestFlight, or the App Store.

**Build Icon**:
The home screen icon that marks the **Install Source**. The Dev Icon (white background with Apple's icon grid) is for Xcode builds, the Beta Icon (blueprint blue background with the icon grid) is for TestFlight, and the standard icon is for the App Store.
_Avoid_: Default icon (ambiguous), environment icon

**Theme Icon**:
An alternate home screen icon matching one **Theme**: the standard artwork on that Theme's background colours. The Default Theme has no separate Theme Icon; it uses the **Build Icon**.

**Icon Choice**:
The icon the user explicitly picked in Settings. While there's no Icon Choice, the app shows the **Build Icon** for its Install Source. An Icon Choice always takes precedence over the Build Icon.
_Avoid_: Icon theme, icon setting

### Day plan

**Plan Window**:
How far ahead from now the outfit advice covers: 1h, 3h, 6h, 12h or Rest of day, chosen in Settings (default Rest of day). Every window starts at the time the plan is made. Fixed windows cross midnight freely; Rest of day runs until midnight in the forecast location's time zone, but covers at least 3 hours. The plan card's title, the weather card's numbers and the chart's shading all show the window.
_Avoid_: Time range, horizon, span (outside code)

**Saved Plan**:
The last day plan the app or the background refresh produced, shared with the widgets (`PlanSnapshot` in code). On launch, a Saved Plan from today for the same location and weather source is shown right away while a fresh one loads. Returning to the app on a later day, or once the plan is stale for the **Plan Window** (30 minutes after the last load for 1h, 1 hour for 3h, 2 hours for 6h, 3 hours for 12h and Rest of day), refetches the weather and remakes the outfit by the same rule. Apart from a new day, automatic refreshes never come closer together than 30 minutes; pull-to-refresh and the Refresh button always refetch.
_Avoid_: Cached plan, snapshot (outside code)

## Relationships

- Each **Theme** except Default has exactly one **Theme Icon**
- The **Icon Choice** is independent of the **Theme**: changing the Theme never changes the icon
- With no **Icon Choice**, the shown icon is the **Build Icon** for the current **Install Source**
- Each **Saved Plan** covers one **Plan Window**; on launch it's only shown when that's still the chosen one, and changing the Plan Window remakes the plan

## Flagged ambiguities

- "Default icon" could mean the App Store icon or the picker's Default option. Resolved: the picker's Default option means "no **Icon Choice**", which shows the **Build Icon**.
