# Changelog

## v0.5.4 — 2026/04/10

### 🎓 Permission Setup on First Launch

- Added first-launch onboarding screen that walks you through required permissions (Storage, Location, Bluetooth)
- Clearly explains the purpose of each permission on screen (compliant with Google Play's "Prominent Disclosure" policy)
- Permission status can be checked and re-configured anytime from Settings

### 🔔 In-App Update History

- Added update notification banner on the home screen (animated pop-in when unread)
- View the full changelog in Markdown format within the app
- Multi-language support (auto-switches between Japanese and English)

---

## v0.5.3 — 2026/04/10

### 📶 Maps Work Smoothly Even Offline

- Migrated tile caching from HTTP server-based delivery to direct MBTiles access
- Native MapLibre loading via `mbtiles://` protocol dramatically improves offline stability
- Fixed blank map issue on Android when returning from background

---

## v0.5.2 — 2026/04/10

### 🌐 Now Available in English

- Introduced type-safe internationalization framework using the slang package
- All UI strings localized to Japanese and English
- One-tap language switching in Settings

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
