# Robert J. Lang Origami — iPhone (SwiftUI)

Native iOS 17+ application with the **actual crawler export** (`RobertLang/langorigami.json`, 2,303 pages). © 2004–2026 Robert J. Lang. Developed for iPhone by Ángel Soto, with permission of Robert J. Lang (credit wording supplied by the requester; verify distribution permission).

## Setup

1. On a Mac: `brew install xcodegen`.
2. In this directory: `xcodegen generate`.
3. Open `RobertLangOrigami.xcodeproj` in Xcode, set your Apple Developer team and signing settings; install an app icon once supplied.
4. Or connect this GitHub repo in Codemagic; configure the App Store Connect integration and the signing workflow in `codemagic.yaml`.

## Catalogue data

The app includes `RobertLang/langorigami.json` as a bundled resource, and checks `https://raw.githubusercontent.com/airsoto/robert_lang_app/main/langorigami.json` for a newer copy. When offline the bundled data still works. Image and PDF links refer to the original website/hosts and require network connectivity. The initial inventory contains 3 crawler errors, URL variants, and pages with dynamic/loading titles.

### Supported screens

Home, Portfolio, Events, Books & Articles, Search and About; automatic route-based classification; keyword/tag filtering; artwork grids, photo galleries, internal links, external resource links and PDFKit reader. Styling follows the supplied black/white/taupe branding. The original site's exact licensed font files are NOT bundled: SwiftUI uses system typography. To achieve an exact font match, supply appropriately licensed typefaces and register them in the project.

### Known differences and limits

The JSON is an extracted inventory rather than a full CMS export. Some tags may be inferred from visible text, original website interactive scripts/search backend cannot be recreated fully from static JSON, and text flattened by the crawler may lose original paragraph structure. The app has not been compiled on macOS/Xcode in this environment. Do not assume App Store distribution or media reproduction rights solely from a credit line.

## GitHub upload from Ubuntu

Create the `robert_lang_app` repository in your GitHub account if it does not exist. Then:

```bash
git init
git add .
git commit -m "Initial iOS app with Lang Origami catalogue"
git branch -M main
git remote add origin https://github.com/airsoto/robert_lang_app.git
git push -u origin main
```
