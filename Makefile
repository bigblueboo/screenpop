APP      := build/Screenpop.app
DEST     ?= /Applications
# A stable signing identity keeps the Screen Recording grant across rebuilds.
IDENTITY ?= $(shell security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $$2; exit}')

.PHONY: app install zip icon test clean

app:
	swift build -c release --arch arm64
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Screenpop $(APP)/Contents/MacOS/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	cp Resources/Info.plist $(APP)/Contents/
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

# Regenerates Resources/AppIcon.icns from Resources/AppIcon-source.png.
icon:
	swift scripts/make-icon.swift

test:
	swift test

clean:
	rm -rf .build build
