APP_NAME := DisplaySplit
APP := build/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications
# Command Line Tools ship swift-testing outside the default search paths, and their
# Testing+Foundation overlay lacks its module files, so cross-import overlays are disabled.
TESTING_FW := $(shell xcode-select -p)/Library/Developer/Frameworks

.PHONY: app install run test clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/$(APP_NAME) $(APP)/Contents/MacOS/
	cp App/Info.plist $(APP)/Contents/
	codesign --force --sign - $(APP)

install: app
	pkill -x $(APP_NAME) || true
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(APP) $(INSTALL_DIR)/

run: install
	open $(INSTALL_DIR)/$(APP_NAME).app

test:
	swift test -Xswiftc -F -Xswiftc $(TESTING_FW) -Xlinker -F -Xlinker $(TESTING_FW) -Xlinker -rpath -Xlinker $(TESTING_FW) \
		-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays

clean:
	rm -rf .build build
