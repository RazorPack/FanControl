SDK     := $(shell xcrun --sdk macosx --show-sdk-path)
SWIFTC  := xcrun swiftc
TARGET  := arm64-apple-macosx14.0
APP     := dist/MacFanControl.app
DMG     := dist/MacFanControl-macos-arm64.dmg
DMG_STAGE := build/dmg
SHARED  := Sources/Shared/SMCClient.swift Sources/Shared/FanProtocol.swift
CFLAGS  := -O -parse-as-library -target $(TARGET) -sdk $(SDK) -strict-concurrency=minimal

.PHONY: all app helper icon dmg run install clean

all: app

helper:
	mkdir -p build
	$(SWIFTC) $(CFLAGS) -framework IOKit -framework Foundation \
		$(SHARED) Sources/Helper/main.swift \
		-o build/macfancontrol-helper

icon:
	mkdir -p build
	swift Resources/GenerateAppIcon.swift build/MacFanControl.iconset
	iconutil -c icns build/MacFanControl.iconset -o build/MacFanControl.icns

app: helper icon
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Helpers $(APP)/Contents/Resources
	$(SWIFTC) $(CFLAGS) -framework SwiftUI -framework AppKit -framework IOKit -framework Foundation \
		$(SHARED) Sources/App/AppLanguage.swift Sources/App/SettingsView.swift Sources/App/MacFanControlApp.swift Sources/App/FanStore.swift Sources/App/ContentView.swift \
		-o $(APP)/Contents/MacOS/MacFanControl
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp build/MacFanControl.icns $(APP)/Contents/Resources/MacFanControl.icns
	cp -R Resources/*.lproj $(APP)/Contents/Resources/
	echo 'APPL????' > $(APP)/Contents/PkgInfo
	cp build/macfancontrol-helper $(APP)/Contents/Helpers/macfancontrol-helper
	chmod 755 $(APP)/Contents/MacOS/MacFanControl $(APP)/Contents/Helpers/macfancontrol-helper
	find $(APP) -name '.DS_Store' -delete
	codesign --force --deep -s - $(APP)

dmg: app
	rm -rf $(DMG_STAGE)
	mkdir -p $(DMG_STAGE)
	cp -R $(APP) $(DMG_STAGE)/MacFanControl.app
	ln -s /Applications $(DMG_STAGE)/Applications
	hdiutil create -volname MacFanControl -srcfolder $(DMG_STAGE) -ov -format UDZO $(DMG)

install: app
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/MacFanControl.app"
	cp -R $(APP) "$(HOME)/Applications/MacFanControl.app"
	xattr -cr "$(HOME)/Applications/MacFanControl.app"
	open "$(HOME)/Applications/MacFanControl.app"

run: app
	open $(APP)

clean:
	rm -rf build dist
