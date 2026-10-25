# Mettiti

A weather-driven outfit suggestion app for iOS, with home screen widgets.

## Language

### Appearance

**Theme**:
The colour scheme of the main screen's background, chosen in Settings. One of Default, Sunset, Ocean, Aurora or Midnight.
_Avoid_: Skin, colour scheme

**Light/Dark**:
Whether the app runs in Light mode, Dark mode or follows the System setting. Separate from the **Theme**. Settings shows it in its Appearance group, alongside the Theme, the App Icon and the cards.
_Avoid_: Appearance (outside code; in Settings it names the group), Mode, Automatic

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

### Main screen

**Wide layout**:
The arrangement of the main screen when it's wide enough to show the cards side by side instead of in one column, such as on the iPhone Duo's open display, a large iPhone turned sideways, or an iPad. Only the width of the app's window decides, never the device: an iPad window made narrow by multitasking gets one column. The last card in the user's order takes the right column and the ones before it stack in order on the left; with only one card shown it sits alone in a centred column. On the widest windows, such as a large iPad in full screen, the two columns stop growing and stay centred. Settings sits in the bottom-right corner instead of the header. Anywhere narrower, the cards stay in one column.
_Avoid_: Duo layout, tablet layout, landscape layout

**Cards**:
The main screen's sections, which the user orders and turns on or off in Settings: Plan, Weather, Location and Wear & bring. A saved order keeps its order and hidden cards when a new card is added; the new card goes in at its default position, shown.
_Avoid_: Today's plan (the Plan card's old name), panels, sections

**Location card**:
A map of where the plan is for, with an unlabelled pin, under the header "Location". For Current Location it follows the GPS fix the weather on screen was loaded for, not every new fix, and the city's name is looked up from it (a fix within a kilometre keeps the name); for a searched city it's that city. The city's name is the Plan card's main title. While there's no location yet, the card shows a desaturated map of roughly where the device is, without a pin.
_Avoid_: Map card, Current Location card

**Skeleton**:
The main screen's only loading state: a card's shapes shimmering where its content will go, until all of that card's content is ready and fades in at once. Shown on the first load, while an outfit is made, and when switching to a **Plan Window** whose outfit has to be made. A refresh behind a plan already on screen never shows it; the plan stays until the new one replaces it.
_Avoid_: Loading state, spinner, placeholder (for the whole state)

### Day plan

**Plan Window**:
How far ahead from now the outfit advice covers: 1h, 3h, 6h, 12h or Rest of day, chosen in Settings (default Rest of day). Every window starts at the time the plan is made. Fixed windows cross midnight freely; Rest of day runs until midnight in the forecast location's time zone, but covers at least 3 hours. The main screen names the window once, in its Plan Window menu; the Plan card's title shows the window's times ("Plan · 2:20 – 5:20 PM"), and the weather card's numbers and the chart's shading cover it.
_Avoid_: Time range, horizon, span (outside code)

**Window Override**:
A **Plan Window** picked with the control on the main screen, e.g. "I'm only going out for an hour". It replaces the Settings default on the main screen until the next launch or the next day, and never changes the default. Switching keeps the weather on screen if it's still fresh for the new window (by the **Saved Plan** staleness rule) and refetches first otherwise; an outfit already made for a window comes back at once while that window's weather has had no **Meaningful Change** since it was made. Those outfits are dropped when a refetch remakes the outfit (a refetch that keeps it keeps them too) or the location or weather source changes. Plans for an overriding window are never saved as the **Saved Plan**, so widgets and background refresh keep following the Settings default.
_Avoid_: Temporary window, quick window

**Saved Plan**:
The last day plan the app or the background refresh produced, shared with the widgets (`PlanSnapshot` in code). On launch, a Saved Plan from today for the same location and weather source is shown right away while a fresh one loads. Returning to the app on a later day, or once the plan is stale for the **Plan Window** (30 minutes after the last load for 1h, 1 hour for 3h, 2 hours for 6h, 3 hours for 12h and Rest of day), refetches the weather and remakes the outfit by the same rule. Apart from a new day, automatic refreshes never come closer together than 30 minutes; pull-to-refresh and the Refresh button always refetch.
_Avoid_: Cached plan, snapshot (outside code)

**Meaningful Change**:
A change in the **Plan Window**'s weather that would change the outfit advice: the window now crosses a sunrise or sunset it didn't (or the other way round), day turned to night (or night to day), the UV band changed (low, moderate, high or above), the chance of rain crossed about 30% or 60%, the high or low moved by about 3°C (5°F), or the kind of weather changed. It's measured against the weather the outfit was made for (`WindowSummary` in code; the check is `differsMeaningfully`), and a different Plan Window or gaining or losing the hourly forecast counts too. An automatic refresh only remakes the outfit after a Meaningful Change; otherwise it keeps the outfit and updates only the weather card and the chart. Pull-to-refresh and changing the location or weather source always remake it. Changing the Plan Window remakes it too, unless an outfit already made for that window has had no Meaningful Change since (see **Window Override**).
_Avoid_: Significant change, weather diff

## Relationships

- Each **Theme** except Default has exactly one **Theme Icon**
- The **Icon Choice** is independent of the **Theme**: changing the Theme never changes the icon
- With no **Icon Choice**, the shown icon is the **Build Icon** for the current **Install Source**
- Each **Saved Plan** covers one **Plan Window**; on launch it's only shown when that's still the chosen one, and changing the Plan Window remakes the plan (or brings back one already made for that window, if it has had no **Meaningful Change** since)
- A **Window Override** never becomes the **Saved Plan**'s window; changing the Settings default ends it
- The widgets and the background refresh follow the **Plan Window** chosen in Settings. The widgets show the **Saved Plan** only while its window runs and it matches that choice, then ask to open the app to update it. The background refresh makes plans by the same staleness rule, but never between 11 PM and 6 AM; it waits until 6 AM instead. Both go by the time where the plan's location is

## Flagged ambiguities

- "Default icon" could mean the App Store icon or the picker's Default option. Resolved: the picker's Default option means "no **Icon Choice**", which shows the **Build Icon**.
