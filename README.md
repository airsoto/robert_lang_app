# Robert J. Lang Origami — iOS 1.1.0 (Build 2)

Independent SwiftUI catalog viewer for **langorigami.com** (iOS 17+, iPhone).

## What's new

- Uses the October 31, 2026 crawler schema v3 (`RobertLang/langorigami.json`) with native collections.
- Browse 535 Artworks, 174 Crease Patterns, 794 Compositions, 241 Published Instructions, 151 Exhibitions, 268 Lectures, 174 Publications and 72 Articles; 6 artist records.
- Five primary tabs: Explore, Portfolio, Events, Library and Search. About and update controls are accessible from Explore.
- Opus, metadata, filters, galleries, related artworks and PDF links displayed in native views.
- Includes catalog metadata for offline use; photos and PDFs are accessed from the official website when online.
- Uses a verified `Info.plist` with orientation/version keys. Existing signing and assets are unchanged.

## Building with Codemagic

Codemagic runs `xcodegen generate`, signs the application and uploads the IPA to App Store Connect. Version and build numbers are in `project.yml`. `submit_to_testflight: false` prevents Codemagic attempting an external TestFlight review before beta contact details are complete; internal TestFlight groups can use the processed build directly.

## JSON data

`RobertLang/langorigami.json` is the **actual app bundle resource** and the optional refresh URL points to the same file on GitHub:

`https://raw.githubusercontent.com/airsoto/robert_lang_app/main/RobertLang/langorigami.json`

To refresh the catalog, replace this file with the output of `langorigami_crawler_v3.py` (schema version `3.0`). No separate hosting service is needed.

## Caveats

- The crawler reported 2 HTTP 404 errors and its `complete` flag is `false`.
- Some compositions, lectures and exhibitions have no cover photograph in the source; the app shows a neutral placeholder rather than an unrelated photo.
- All photographs, artwork, texts and diagrams belong to their respective rightsholders. This repository and its credits do **not** represent proof of Robert J. Lang's permission to distribute the app.
- This release's source has passed Swift syntax checks on Linux; a full iOS compile must be confirmed by Xcode/Codemagic.

App adaptation: Ángel Soto. Original site: https://langorigami.com/.
