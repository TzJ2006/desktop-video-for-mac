# UI Architecture

This folder explains how to extend the SwiftUI based preference window.

## Adding a new feature card

1. Create a view model in `ViewModels/` (e.g. `NewFeatureVM`).
2. Create a screen in `UI/Screens/` (e.g. `NewFeatureView`) that uses reusable components like `CardSection` and `FormRows`.
3. Register a new case in `SidebarSelection` and provide a `SidebarItem` entry in `SidebarView`.
4. Present the view in `AppMainWindow` switch statement.

No changes to shared components are required.

## Mapping from old controllers

| Old Controller | New SwiftUI View |
| --- | --- |
| `ContentView` | `AppMainWindow` |
