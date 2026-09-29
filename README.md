# Screenpop

A menu bar app for macOS. Press ⌃⇧4, drag a rectangle, and Screenpop cuts the subject out of its background on-device with Apple's Vision framework. The cutout goes to the clipboard as a transparent PNG and is saved to `~/Pictures/Screenpop`. A thumbnail appears in the corner: drag it into any app, or click it to show the file in Finder. While you're pasting, `gpt-6-luna` looks at the capture and renames the file to something you can search for, like `stripe-checkout-card-declined.png`.

## Run

```sh
make install          # builds, signs, copies to /Applications, launches
```

Run it from a terminal on the Mac itself (not over SSH). Signing needs the login keychain unlocked, and a stable signature is what keeps the Screen Recording permission across rebuilds. If a Mac's development certificate is stale, the app builds but refuses to launch ("Launchd job spawn failed", code 163). Run `make install IDENTITY=-` there to sign ad-hoc instead. On first launch macOS asks for Screen Recording access; grant it, then reopen Screenpop.

The OpenAI key is looked up in this order:

1. The Keychain (paste it into Settings… in the menu)
2. `OPENAI_API_KEY` in the environment
3. `~/.secrets/screenpop/openai.env` (`OPENAI_API_KEY=sk-…`)

Without a key, captures still work and keep a timestamp name.

Menu bar → Settings… changes the shortcut, the save folder, background removal, copying to the clipboard, and open-at-login. With background removal off, you get a plain named screenshot. If Vision finds no subject (a text-only UI, say), you get the full rectangle.

To test the pipeline without the UI:

```sh
build/Screenpop.app/Contents/MacOS/Screenpop --process photo.png out.png
```

## Quality gates

```sh
make test             # swift test: naming, slugging, API parsing
make app              # release build + codesign
```

The icon art (`Resources/AppIcon-source.png`) came from `genai-image`. `make icon` masks it to the macOS icon shape and rebuilds `Resources/AppIcon.icns`.
