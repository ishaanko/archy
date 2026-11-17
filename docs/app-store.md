# App Store submission

Everything to paste into App Store Connect for archy 1.0, and the steps to ship it.

## Steps

1. Accept the updated Apple Developer Program License Agreement at [developer.apple.com/account](https://developer.apple.com/account). Until the account holder does, signing fails with "PLA Update available".
2. In [App Store Connect](https://appstoreconnect.apple.com), create the app: platform iOS, name `archy`, bundle ID `com.dubhacks.archy`, SKU `archy-ios`.
3. Upload a build: `cd ios && scripts/release.sh`. It appears under TestFlight after about 10 to 30 minutes.
4. Install it from TestFlight on an iPhone with LiDAR and run one full scan, from Start scan to the 3D result. The Simulator can't test this.
5. Fill in the listing from the sections below and upload the screenshots.
6. Pick the build on the version page and submit for review.

## Listing

| Field | Value |
| --- | --- |
| Name | archy |
| Subtitle | Foot scan, arch and insoles |
| Primary category | Health & Fitness |
| Secondary category | Utilities |
| Price | Free |
| Privacy policy URL | https://tryarchy.vercel.app/privacy.html |
| Support URL | https://tryarchy.vercel.app/support.html |
| Marketing URL | https://tryarchy.vercel.app |
| Copyright | 2026 Pranav Narsipur |

**Promotional text**

Scan your foot in 3D, see your arch in plain words and shape an insole around it. Everything stays on your iPhone.

**Description**

archy helps you understand your feet.

Scan a foot with your iPhone's LiDAR sensor and archy builds a 3D model, measures its length, width and arch lift, and tells you in plain words whether your arch reads flat or normal. No LiDAR? Measure by hand with a ruler and tape, and archy walks you through each step.

SCAN
• Guided 3D foot scan on iPhones with LiDAR (iPhone 12 Pro and later Pro models)
• Turn the finished model around and share it as a file
• A sample scan is included, so you can explore on any iPhone

MEASURE
• Step-by-step hand measurements with pictures
• Arch Height Index, navicular drop and width-to-length ratio
• Millimeters or inches

INSOLE
• Shape an insole concept around your measurements
• Pick arch support and a material, and see the load in Earth, Moon, Mars and zero gravity
• Save a request and share it with a maker for a quote. Nothing is ordered or charged in the app

TRAIN
• Guided foot exercises: short foot, toe yoga, heel raises and balance
• A spoken coach counts you through each set

PRIVATE
• No account, no ads, no tracking
• Your answers, photos and scans stay on your iPhone

archy is a screening and education tool. It is not a medical device, its measurements are not clinically validated, and it does not diagnose or treat any condition. See a clinician about foot pain or any health concern. archy is not affiliated with NASA.

**Keywords** (100 characters max)

```
arch,flat feet,insole,orthotic,lidar,3d scan,exercise,plantar,podiatry,measure,foot pain,heel,toes
```

**What's New**: not needed for the first version.

## App privacy

Answer "No, we do not collect data from this app". The label reads **Data Not Collected**. This is true for Release builds: they make no network requests, and the Debug-only voice proxy is compiled out (`GuidanceVoice.offersGrok`).

## Age rating

Answer None or No to everything except:

- **Medical or treatment information**: Infrequent/Mild. The app asks about foot pain and shows exercises.

Expected rating: 4+ (Apple may assign a higher tier for the medical answer).

## Other questions

- **Export compliance**: no encryption. `ITSAppUsesNonExemptEncryption` is already `false`, so App Store Connect won't ask.
- **Content rights**: no third-party content.
- **Advertising identifier**: not used.
- **Sign-in required**: no.

## Notes for the reviewer

```
archy needs no account or sign-in.

LiDAR: the 3D foot scan uses Object Capture, which needs an iPhone with LiDAR
(iPhone 12 Pro or later Pro/Pro Max). On other devices the Scan tab says
"Scanning needs an iPhone with LiDAR" and offers "View a sample scan", which opens
a bundled scan so the viewer, measurements and sharing can all be reviewed.
Everything else works on any iPhone: Home > "Try an example" or "Measure by hand",
the Insole tab and the Train tab.

To test a real scan: Scan tab > Start scan. Place a bare foot on a plain floor in
good light and walk the phone slowly around it. Processing happens on the device and
takes a few minutes.

Insole requests: "Share for a quote" only opens the iOS share sheet with a file.
Nothing is ordered, sold or charged, so there is no in-app purchase.

Health: the app is an educational screening tool. It gives no diagnosis or
treatment and says so in the app and in the description. It is not affiliated
with NASA; the research list links to public nasa.gov pages.

Privacy: the app makes no network requests. All data stays on the device.
```

Contact details for the reviewer: your name, phone and email.

## Screenshots

App Store Connect needs 6.9-inch iPhone screenshots (1320 x 2868). Seven are ready in `ios/e2e-artifacts/appstore/`, numbered in upload order: scan result, arch results, home, insole, Mars insole, exercises, coach. The folder is not in git.

To regenerate the full set (it lands in `ios/e2e-artifacts/light/`):

```sh
cd ios && scripts/e2e.sh light "iPhone 17 Pro Max"
```
