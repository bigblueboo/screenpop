# Screenpop

A menu bar app for macOS. Press ⌃⇧4, drag a rectangle, and Screenpop cuts the subject out of its background on-device with Apple's Vision framework. The cutout goes to the clipboard as a transparent PNG and is saved to `~/Pictures/Screenpop`. A thumbnail appears in the corner: drag it into any app, or click it to show the file in Finder. While you're pasting, `gpt-6-luna` looks at the capture and renames the file to something you can search for, like `stripe-checkout-card-declined.png`.

## Install

Needs macOS 14 (Sonoma) or later, on Apple Silicon or Intel.

```sh
brew install --cask bigblueboo/tap/screenpop
```

Or download `Screenpop-<version>.zip` from [Releases](https://github.com/bigblueboo/screenpop/releases), unzip it, and drag Screenpop to Applications. Releases are notarized, so they open without a Gatekeeper warning.

On first launch a setup window walks you through the rest:

1. **Allow screen recording.** Click Allow…, then turn on Screenpop in System Settings. If macOS offers Quit & Reopen, take it; the window comes back with the step ticked.
2. **Add your OpenAI key** (optional). It's saved in your Keychain. Without one, files keep a timestamp name.
3. **Try it:** press ⌃⇧4 and drag over anything.

`brew upgrade --cask screenpop` updates it. Releases share one signature, so Screen Recording stays allowed across updates.

### From source

Needs Xcode or the Command Line Tools (`xcode-select --install`). In Terminal on the Mac itself (signing needs the login keychain unlocked, so not over SSH):

```sh
gh repo clone bigblueboo/screenpop ~/dev/screenpop
cd ~/dev/screenpop
make install          # build, sign, copy to /Applications, launch
```

`git pull && make install` updates it.

`make install` signs with your Apple Development certificate when it finds one, which keeps the Screen Recording permission across rebuilds. Without one (or with the keychain locked) it signs ad-hoc, and macOS asks for Screen Recording again after each rebuild. If macOS refuses to launch the certificate-signed build ("Launchd job spawn failed", code 163, usually a stale certificate), it re-signs ad-hoc and launches again. `make install IDENTITY=-` skips the certificate entirely.

A source build and a Homebrew install have different signatures, so switching between them means allowing Screen Recording again.

## Use

- **⌃⇧4** starts a capture. Space switches to window capture and Esc cancels.
- **Remove Background** and **Copy to Clipboard** are toggles in the menu, both on by default. With background removal off you get a plain named screenshot. If Vision finds no subject (a text-only window, say), you get the full rectangle.
- **Settings…** changes the shortcut and save folder, and stores the OpenAI key. The version number is at the bottom.

Naming sends a 512-pixel JPEG of each capture to OpenAI and nothing else. The key is looked up in this order:

1. The Keychain, which is where Settings saves it
2. `OPENAI_API_KEY` in the environment, when launched from a shell
3. `~/.secrets/screenpop/openai.env`, as `OPENAI_API_KEY=sk-…`

## Quality gates

```sh
make test                 # swift test: naming, slugging, API parsing
make app                  # native-arch build, signed for local use
make bundle UNIVERSAL=1   # arm64 + x86_64 build (needs full Xcode)
```

Two hooks for checking things without a screen:

```sh
build/Screenpop.app/Contents/MacOS/Screenpop --process photo.png out.png   # cutout + naming, no UI
open build/Screenpop.app --args --snapshot /tmp/shots                      # renders the windows to PNGs
```

The icon art (`Resources/AppIcon-source.png`) came from `genai-image`. `make icon` masks it to the macOS icon shape and rebuilds `Resources/AppIcon.icns`.

## Releasing

```sh
make release VERSION=1.2.0
```

[`scripts/release.sh`](scripts/release.sh) checks everything it needs before building. It then makes a universal build, signs it with Developer ID, notarizes and staples it, tags `v1.2.0`, uploads the zip to a GitHub release, and updates `Casks/screenpop.rb` in [bigblueboo/homebrew-tap](https://github.com/bigblueboo/homebrew-tap) from [`packaging/screenpop.rb`](packaging/screenpop.rb). The version shown in the app comes from the tag; the build number is the commit count.

One-time setup on the Mac you release from:

1. **Developer ID certificate.** Xcode › Settings › Accounts › your team › Manage Certificates › + › Developer ID Application. This needs a paid Apple Developer Program membership, and you must be the team's Account Holder.
2. **Notarization credentials.** Make an app-specific password at [account.apple.com](https://account.apple.com) (Sign-In and Security › App-Specific Passwords), then:

   ```sh
   xcrun notarytool store-credentials screenpop --apple-id <your Apple ID> --team-id <team ID>
   ```

   The team ID is the 10-character code in parentheses after your name in the certificate.
3. **`gh auth login`**, with push access to this repo and the tap.

## License

MIT. See [LICENSE](LICENSE).
