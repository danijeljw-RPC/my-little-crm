# Google Play store listing assets

Upload-ready assets for the Google Play listing of My Little CRM
(`com.repasscloud.mylittlecrm`).

| Asset | File(s) | Size | Play requirement |
| --- | --- | --- | --- |
| App icon | `app-icon-512.png` | 512 × 512 | PNG/JPEG, ≤ 1 MB, 512 × 512 |
| Featured graphic | `featured-graphic-1024x500.png` | 1024 × 500 | PNG/JPEG, ≤ 15 MB, 1024 × 500 |
| Phone screenshots | `screenshots/phone/*.png` (6) | 1080 × 1920 (9:16) | 2–8, each side 320–3,840 px |
| 7-inch tablet screenshots | `screenshots/tablet-7in/*.png` (6) | 1080 × 1920 (9:16) | up to 8, each side 320–3,840 px |
| 10-inch tablet screenshots | `screenshots/tablet-10in/*.png` (6) | 1620 × 2880 (9:16) | up to 8, each side 1,080–7,680 px |

All files are 24-bit PNGs (no alpha), each well under 1 MB. Upload screenshots
in filename order.

## How they're made

The screenshots are rendered from the real app widgets with fictional sample
data (no real companies or people), so they always match the current UI:

- `tool/store_listing/screenshots_test.dart` pumps the app at each device size
  and captures the screens.
- `tool/store_listing/graphics.py` builds the icon (launcher art on white) and
  the featured graphic, and flattens the screenshots.

Regenerate everything after UI changes with:

```sh
tool/store_listing/generate.sh
```

Requires Flutter and Python 3 with Pillow. The script is not part of
`flutter test` (it lives outside `test/`), so CI is unaffected.
