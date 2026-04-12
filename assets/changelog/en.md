# Changelog

## v0.5.6 — 2026/04/12

### 📍 Open Points in Google Maps from Detail Panel

- Added "Open in Google Maps" button to the point detail panel
- On Android, launches Google Maps app directly via geo: intent
- Falls back to browser on PC or when the app is not installed

### 🗑️ Long-Press Delete from Detail Panel

- Added a "Delete" button to all feature and photo detail panels
- Requires a 1-second long press to prevent accidental deletion
- Red gauge animation provides visual feedback during the hold

### 🐛 Bug Fixes

- Fixed EXIF location and timestamp data being lost when importing photos from gallery (bypassed Android Photo Picker's EXIF stripping via native file copy)
- Fixed crash when loading images with NaN GPS coordinates from EXIF (0/0 Ratio)
- Suppressed tile server success logs to reduce console noise

---

## v0.5.5 — 2026/04/11

### 🏷️ Rebranded to "RootMap GIS"

- Application name changed from "k_maps" to "RootMap GIS"
- Unified app name display across all platforms (Android / Windows / Web)
- Internal package name changed to `root_maps`
- Google Drive sync folder renamed to "RootMap GIS Projects"

### 📝 Auto-Fill Version & Device Info in Feedback Form

- Feedback form now auto-fills app version and device model when opened
- Makes bug reports smoother and more informative

---

## v0.5.4 — 2026/04/10

### 🌐 Now Available in English

- Introduced type-safe internationalization framework using the slang package
- All UI strings localized to Japanese and English
- One-tap language switching in Settings

### 📶 Maps Work Smoothly Even Offline

- Migrated tile caching from HTTP server-based delivery to direct MBTiles access
- Native MapLibre loading via `mbtiles://` protocol dramatically improves offline stability
- Fixed blank map issue on Android when returning from background

### 🔤 Adjustable UI Size (7 Levels)

- Adjust the size of text and UI elements in 7 levels (XS / S / M− / M / M+ / L / XL) from Settings → General
- Changes apply instantly with a simple slider — no restart required

### 📖 In-App User Guide

- Access the user guide from the home screen AppBar
- Available in Japanese and English (auto-switches with app language)
- Custom Markdown renderer displays actual app icons inline within the guide
- *Note: Guide content is AI-generated*

### 🎓 Permission Setup on First Launch

- Added first-launch onboarding screen that walks you through required permissions (Storage, Location, Bluetooth)
- Clearly explains the purpose of each permission on screen (compliant with Google Play's "Prominent Disclosure" policy)
- Permission status can be checked and re-configured anytime from Settings

### 🔔 In-App Update History

- Added update notification banner on the home screen (animated pop-in when unread)
- View the full changelog in Markdown format within the app
- Multi-language support (auto-switches between Japanese and English)

### 📱 Auto-Hide Android Navigation Bar

- 3-button navigation bar (◁□○) is now hidden by default for a full-screen experience
- Swipe from the bottom edge to temporarily reveal; auto-hides after 3 seconds

---

## v0.5.1 — 2026/04/02

### 📊 Smarter Data Search & Editing

- Added QGIS-style filter functionality (filter features with expressions like `"area" > 100`)
- Feature duplication (create new features based on existing data)
- Sub-table timestamp display
- Eliminated flickering when toggling selected feature highlights

### 🖼️ Freely Transform Images on the Map

- Implemented Photoshop-style transform handles for OverlayImageNode
- Drag handles to move, scale, and rotate intuitively
- Improved hit-test accuracy so even small images are easy to manipulate
- Transform results reflected on the map instantly

### 📋 Published to Google Play Internal Testing

- Created and published privacy policy on GitHub
- Configured AAB build and signing for Google Play

### 🖥️ Windows Support Temporarily Paused

- Windows development paused due to maplibre_webview performance falling short of requirements and significant behavioral differences from maplibre core
- Will resume once native Windows support is available in maplibre

---

## v0.5.0 — 2026/03/31

### 🔫 Field Surveying with Laser Rangefinder

- Connection and real-time data retrieval with TruPulse 360R (Bluetooth Classic)
- Instantly record distance, azimuth, and inclination measurements as points
- Closure adjustment (Compass rule / Transit rule) ensures accuracy
- Magnetic declination, instrument height, and target height corrections
- Real-time closure ratio display with instant accuracy warnings
- Automatic conversion from survey points to Line/Polygon

### ⚡ Overall App Stability Improvements

- Full Riverpod normalization (removed GlobalConfig, unified providers) for cleaner state management
- Async race condition prevention with Completer introduction
- Declarative settings framework (SettingDef + SettingsStore)
- Select tool redesigned for cross-layer traversal with priority cycling
- WKB parsing delegated to geobase & multi-geometry support

### 🛠️ Small But Important Fixes

- AppBar notification center (integrated SnackBar into structured notifications)
- Global folder custom path settings & containment checking
- GeoJSON import automatically splits layers by geometry type
- Restored Windows GPS position, marker, and initial jump functionality

---

## v0.4.0 — 2026/03/18

### ☁️ Share & Backup Data via Google Drive

- Google Sign-In authentication and Drive API integration
- Folder-level clone and manual sync (Push/Pull)
- Drive info persisted in .kmeta.json for state restoration on next launch
- Auto-sync checks with visual sync status icons
- Drive sync UI integrated into title bar for one-tap access

### 📊 Attribute Table Made Easier to Use

- QGIS-style filter for quick searching through large datasets
- Feature duplication (one-click copy of similarly structured data)

### 🚀 Faster Data Loading

- Migrated maplibre from vendored fork to official pub.dev release
- Large file splitting (feature_converter, layer_drawer_tiles, sync_engine, etc.)
- GeoPackage loading acceleration (N+1 query elimination, parallelization, Isolate)

---

## v0.3.3 — 2026/03/11

### 📥 Download Maps Ahead for Offline Use

- Implemented offline basemap cache functionality
- Bulk download with area & zoom level selection
- Fixed SymbolStyleLayer rendering issues
- Fixed feature layers hiding behind basemap on network change
- Added Drive auto-sync check functionality
- GeoPackageTile refactoring & drag-move bug fix

---

## v0.3.2 — 2026/03/10

### 📷 Pick Photos from Your Gallery

- Replaced camera capture with gallery import (easier to use existing photos)
- LayerDrawer UI unification (single add button, folder action menu)

---

## v0.3.1 — 2026/03/09

### 🔧 Layer Panel Cleanup

- Split the massive God Object LayerDrawer class into manageable pieces
- LayerDrawerService extraction & ConsumerWidget migration for better maintainability

---

## v0.3.0 — 2026/03/09

### 🗺️ Blazing Fast Map Rendering

- Full map engine migration from FlutterMap to MapLibre
- High-performance rendering with GeoJSON Source + Style Layers
- Point clustering (supercluster) handles massive marker counts smoothly
- GPU-accelerated photo markers (SymbolStyleLayer)
- Windows performance optimization (vertex marker GPU rendering, batchSetPaintProperties)
- Unified settings screen UI (responsive Split View)
