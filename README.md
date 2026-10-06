# Screenpop

A menu bar app for macOS. Press ⌃⇧4, drag a rectangle, and Screenpop cuts the subject out of its background on-device with Apple's Vision framework. The cutout goes to the clipboard as a transparent PNG and is saved to `~/Pictures/Screenpop`. A thumbnail appears in the corner: drag it into any app, or click it to show the file in Finder. While you're pasting, `gpt-6-luna` looks at the capture and renames the file to something you can search for, like `stripe-checkout-card-declined.png`.

## Install

You need an Apple Silicon Mac on macOS 14 or later, with Xcode or the Command Line Tools (`xcode-select --install`).

In Terminal on that Mac (not over SSH, since signing needs the login keychain unlocked):

```sh
gh repo clone bigblueboo/screenpop ~/dev/screenpop
cd ~/dev/screenpop
make install
```

This builds the app, copies it to `/Applications`, and launches it. A scissors icon appears in the menu bar. Then:

1. Allow Screen Recording when macOS asks, and reopen Screenpop (`open -a Screenpop`).
2. Click the scissors › Settings…, paste your OpenAI key and press Return. Turn on Open at login while you're there.

To update later: `git pull && make install`.

### Signing

`make install` signs with your Apple Development certificate when it can find one, which keeps the Screen Recording permission across rebuilds. If there's no certificate or the keychain is locked, it signs ad-hoc instead. If macOS refuses to launch the certificate-signed build (a stale certificate shows up as "Launchd job spawn failed", code 163), it re-signs ad-hoc and launches again. Ad-hoc builds behave the same, except macOS asks for Screen Recording again after each rebuild. `make install IDENTITY=-` skips the certificate entirely.

### On a Mac without Xcode

Build a zip on a Mac that has Xcode:

```sh
make zip            # writes build/Screenpop.zip
```

Copy it over with `scp` or AirDrop, then on the target Mac:

```sh
ditto -x -k Screenpop.zip /Applications
xattr -dr com.apple.quarantine /Applications/Screenpop.app   # needed after AirDrop or a download
open /Applications/Screenpop.app
```

## Use

- **⌃⇧4** starts a capture. Space switches to window capture and Esc cancels.
- **Remove Background** and **Copy to Clipboard** are toggles in the menu, both on by default. With background removal off you get a plain named screenshot. If Vision finds no subject (a text-only window, say), you get the full rectangle.
- **Settings…** changes the shortcut and save folder, and stores the OpenAI key.

The OpenAI key is looked up in this order:

1. The Keychain, which is where Settings saves it
2. `OPENAI_API_KEY` in the environment, when launched from a shell
3. `~/.secrets/screenpop/openai.env`, as `OPENAI_API_KEY=sk-…`

Without a key, captures still work and keep a timestamp name.

## Quality gates

```sh
make test           # swift test: naming, slugging, API parsing
make app            # release build + codesign into build/Screenpop.app
```

To run the cutout and naming steps without the UI:

```sh
build/Screenpop.app/Contents/MacOS/Screenpop --process photo.png out.png
```

The icon art (`Resources/AppIcon-source.png`) came from `genai-image`. `make icon` masks it to the macOS icon shape and rebuilds `Resources/AppIcon.icns`.
