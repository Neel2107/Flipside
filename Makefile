APP := build/Flipside.app

# The Command Line Tools ship Swift Testing but SwiftPM only finds it by itself under Xcode.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIB := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -F$(CLT_FRAMEWORKS) -Xlinker -F$(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_LIB)
endif

.PHONY: app run install test e2e previews clean

app:
	./scripts/build-app.sh

run: app
	open $(APP)

# Replaces any copy in /Applications and starts the new one.
install: app
	-osascript -e 'quit app "Flipside"' 2>/dev/null
	rm -rf /Applications/Flipside.app
	cp -R $(APP) /Applications/Flipside.app
	open /Applications/Flipside.app

test:
	swift test $(TEST_FLAGS)

# Rearranges a temporary virtual display for a few seconds; needs exactly one real display.
e2e:
	swift run flipside-e2e

previews:
	swift build --product Flipside
	.build/debug/Flipside --render-previews build/previews

clean:
	rm -rf .build build
