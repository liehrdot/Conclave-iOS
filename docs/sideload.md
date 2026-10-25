# Putting the app on an iPhone

Without a paid Apple Developer account an iPhone only runs apps that you sign yourself.
[iloader](https://github.com/nab138/iloader) (free, open source) does that on Windows with a normal
Apple ID. The catch: a self-signed app runs for 7 days, then it has to be installed again, and only
3 such apps can be on the phone at the same time (Conclave Table is one of them).

## Getting the app

Open the repo on GitHub › Actions › "CI" › the newest run on `main` › "Artifacts" at the bottom ›
`conclave-ios`. It downloads as a zip; unzip it to get `Conclave.ipa`.

## Installing it

Since about 2026-10-12 Apple refuses the sign-in of tools that pretend to be a Windows or Android
device ("Anisette" data), with errors -80045 / -80046. What works (Flo, 2026-10-24): iloader with the
Anisette server "Jkcoxson (Mac)". That server only lends the device data; the Apple ID password
still goes straight to Apple.

1. Install iTunes **from apple.com** (iloader needs its device driver; the Microsoft Store version
   doesn't work), then iloader.
2. In iloader's settings, set "Anisette Server" to **Jkcoxson (Mac)**.
3. Connect the iPhone by cable and tap "Trust" on the phone.
4. Sign in with your Apple ID in iloader and install `Conclave.ipa`. Don't retry many times in a row
   if it fails: Apple can block an Apple ID from signing for a while.
5. On the iPhone: Settings › General › VPN & Device Management › your Apple ID › Trust.
6. Developer Mode, if iOS asks: Settings › Privacy & Security › Developer Mode › on, then restart.
7. After 7 days the app no longer opens: install the newest `.ipa` again from step 4. Your data stays.
