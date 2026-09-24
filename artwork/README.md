# Peekaboo icon

`Peekaboo.png` is the original generated artwork. The macOS sizes live in `Peekaboo/Assets.xcassets/AppIcon.appiconset`; Xcode compiles them into the app icon. The outer background is transparent.

Generated with the built-in imagegen tool, then resized with macOS `sips` for the asset catalog.

The matching menu bar icon is a template PDF in `Peekaboo/Assets.xcassets/MenuBarIcon.imageset`. Its editable source is `make-menu-icon.swift`; regenerate it from the project root with `swift artwork/make-menu-icon.swift`. macOS supplies its light or dark appearance.

The artwork was generated before the app was renamed to Peekaboo. Original prompt:

> Use case: logo-brand. Create a polished production macOS app icon for HideShow, a small desktop utility that instantly hides and brings forward application windows using keyboard shortcuts. One icon only, square 1024x1024 canvas, no presentation mockup. A rich tangerine-orange rounded-square macOS app tile, subtle finely crafted dimensional surface and restrained soft lighting. Centered large symbol of two offset application windows: a darker burnt-orange/graphite rear window partly concealed, and a bright warm-white front window emerging forward. Both simple rounded rectangles with a clean thin title-bar line; minimal abstract window chrome, no content or lettering. Strong simple silhouette and crisp edges that remain legible at 32 pixels. Straight-on orthographic view, intentional precise geometry, generous balanced spacing. Icon tile occupies about 88 percent of canvas width/height, consistent macOS rounded corners with genuinely transparent outer background and gentle restrained shadow. No words, no letters, no keyboard, no eyes, no arrows, no badges, no extra ornaments. This is the final app icon asset, not a screenshot or marketing graphic.

`social-preview.png` is the 1280×640 GitHub social preview, which GitHub shows when the repository link is shared. It combines the 512-pixel app icon with the README tagline. Upload it under the repository's **Settings → General → Social preview**.
