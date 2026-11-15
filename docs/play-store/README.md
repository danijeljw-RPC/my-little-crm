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

---

## Short description (75 characters)

Keep a record of who you spoke with, what was said, and what they promised.

## Full description (about 1,900 characters)

My Little CRM is a simple, private way to keep track of your own conversations with companies, services and people.

Called your energy provider, bank, insurer or landlord? Write down who you spoke with, what was discussed and what was promised, so the next time you call you have the details in front of you.

WHY KEEP YOUR OWN RECORD?
Important conversations get scattered across phone calls, emails, chats and letters. When a promised callback never comes or a refund goes missing, your own notes are what help you stay on top of it.

LOG EVERY INTERACTION
• Record the company or person you dealt with
• Note how you were contacted: phone, email, SMS, letter, chat or other
• Save the name of the person you spoke to
• Keep reference, ticket and case numbers together
• Write down any commitment they made, such as "refund within 5 business days"
• Add a summary of what was said, with the date and time

NEVER MISS A FOLLOW-UP
Set a follow-up due date on any interaction. The Follow-ups screen shows everything still outstanding, so you know when it's time to chase things up. Mark them done when they're resolved.

SEE THE FULL HISTORY
Open any company or person to see every interaction with them in order, so you can quickly see what was said before.

SEARCH
Find a past conversation, reference number or commitment in seconds.

EXPORT YOUR HISTORY
Export a history as a PDF to share, print or attach to a complaint, or as a JSON file for your own records.

PRIVATE BY DESIGN
• No account or sign-up
• Works fully offline
• Your data stays on your device and is never uploaded
• No ads, no analytics, no tracking

My Little CRM is made for personal, at-home use: an easy way to keep your own record and stay ahead.
