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

## Relationships

- Each **Theme** except Default has exactly one **Theme Icon**
- The **Icon Choice** is independent of the **Theme**: changing the Theme never changes the icon
- With no **Icon Choice**, the shown icon is the **Build Icon** for the current **Install Source**

## Flagged ambiguities

- "Default icon" could mean the App Store icon or the picker's Default option. Resolved: the picker's Default option means "no **Icon Choice**", which shows the **Build Icon**.
