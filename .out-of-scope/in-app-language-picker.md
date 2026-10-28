# In-app language picker

Mettiti does not have its own language setting. It follows the language iOS chooses for the app.

## Why this is out of scope

The app ships more than one localization (English and Italian), so iOS already shows a
per-app **Language** option on Mettiti's page in the Settings app. Choosing a language there
relaunches the app in that language, and the widgets and the outfit advice follow it with no
extra work: the advice's language comes from `Bundle.main.preferredLocalizations`
(`OutfitAdvisor.responseLanguage()`), which iOS sets.

A picker inside the app would duplicate that setting and add problems of its own:

- The app would have to override the system language and restart before the change took effect.
- The widgets wouldn't follow unless the choice went through the App Group and the widget
  extension applied it too, so the app and widgets could easily disagree.
- There would be two places to change the language, and they could contradict each other.

What the app does have to get right is reacting when the language changes. That's tracked as a
bug, separate from this.

## Prior requests

- #159: "Add language selection in in app settings"
