SDK     := $(shell xcrun --sdk macosx --show-sdk-path)
SWIFTC  := xcrun swiftc
TARGET  := arm64-apple-macosx14.0
APP     := dist/FanControl.app
SHARED  := Sources/Shared/SMCClient.swift Sources/Shared/FanProtocol.swift
CFLAGS  := -O -parse-as-library -target $(TARGET) -sdk $(SDK) -strict-concurrency=minimal

.PHONY: all app helper icon run install clean

all: app

helper:
	mkdir -p build
	$(SWIFTC) $(CFLAGS) -framework IOKit -framework Foundation \
		$(SHARED) Sources/Helper/main.swift \
		-o build/fancontrol-helper

icon:
	mkdir -p build
	swift Resources/GenerateAppIcon.swift build/FanControl.iconset
	iconutil -c icns build/FanControl.iconset -o build/AppIcon.icns

app: helper icon
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Helpers $(APP)/Contents/Resources
	$(SWIFTC) $(CFLAGS) -framework SwiftUI -framework AppKit -framework IOKit -framework Foundation \
		$(SHARED) Sources/App/FanControlApp.swift Sources/App/FanStore.swift Sources/App/ContentView.swift \
		-o $(APP)/Contents/MacOS/FanControl
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp build/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp -R Resources/*.lproj $(APP)/Contents/Resources/
	echo 'APPL????' > $(APP)/Contents/PkgInfo
	cp build/fancontrol-helper $(APP)/Contents/Helpers/fancontrol-helper
	chmod 755 $(APP)/Contents/MacOS/FanControl $(APP)/Contents/Helpers/fancontrol-helper
	find $(APP) -name '.DS_Store' -delete
	codesign --force --deep -s - $(APP)

install: app
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/FanControl.app"
	cp -R $(APP) "$(HOME)/Applications/FanControl.app"
	xattr -cr "$(HOME)/Applications/FanControl.app"
	open "$(HOME)/Applications/FanControl.app"

run: app
	open $(APP)

clean:
	rm -rf build dist
