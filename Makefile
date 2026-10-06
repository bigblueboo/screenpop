APP      := build/Screenpop.app
DEST     ?= /Applications
# Version comes from the latest v* tag; the build number is the commit count.
VERSION  ?= $(or $(shell git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//'),0.1.0)
BUILD    ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
# A stable signing identity keeps the Screen Recording grant across rebuilds.
IDENTITY ?= $(shell security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $$2; exit}')

# UNIVERSAL=1 builds arm64 + x86_64 (needs full Xcode); the default is this Mac's arch.
ifdef UNIVERSAL
SWIFT_FLAGS := --arch arm64 --arch x86_64
BINARY      := .build/apple/Products/Release/Screenpop
else
SWIFT_FLAGS :=
BINARY      := .build/release/Screenpop
endif

.PHONY: bundle app install zip release icon test clean

# Unsigned, version-stamped build/Screenpop.app.
bundle:
	swift build -c release $(SWIFT_FLAGS)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	cp Resources/Info.plist $(APP)/Contents/
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(APP)/Contents/Info.plist
	plutil -replace CFBundleVersion -string "$(BUILD)" $(APP)/Contents/Info.plist
	@echo "Screenpop $(VERSION) ($(BUILD)): $$(lipo -archs $(APP)/Contents/MacOS/Screenpop)"

# Signed for local use with Apple Development, or ad-hoc when that isn't available.
app: bundle
	@codesign --force --options runtime --timestamp=none --sign "$(IDENTITY)" $(APP) 2>/dev/null \
		|| { echo "warning: couldn't sign with '$(IDENTITY)' (keychain locked?); signing ad-hoc." \
		     "Screen Recording permission will reset on each rebuild."; \
		     codesign --force --options runtime --sign - $(APP); }
	@codesign -dvv $(APP) 2>&1 | grep -E '^(Authority|Signature)=' | head -1

install: app
	@pkill -x Screenpop || true
	rm -rf $(DEST)/Screenpop.app
	ditto $(APP) $(DEST)/Screenpop.app
	@open $(DEST)/Screenpop.app 2>/dev/null \
		|| { echo "macOS refused to launch the certificate-signed build; re-signing ad-hoc."; \
		     codesign --force --options runtime --sign - $(DEST)/Screenpop.app && open $(DEST)/Screenpop.app; }

# build/Screenpop.zip, for copying to a Mac without Xcode.
zip: app
	ditto -c -k --keepParent $(APP) build/Screenpop.zip
	@echo "wrote build/Screenpop.zip"

# Universal, Developer ID-signed, notarized; publishes a GitHub release and the Homebrew cask.
release:
	scripts/release.sh $(VERSION)

# Regenerates Resources/AppIcon.icns from Resources/AppIcon-source.png.
icon:
	swift scripts/make-icon.swift

test:
	swift test

clean:
	rm -rf .build build
