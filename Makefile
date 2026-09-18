XCODEBUILD := xcodebuild -project Peekaboo.xcodeproj -scheme Peekaboo -destination 'platform=macOS,arch=$(shell uname -m)' -derivedDataPath .build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
APP := .build/Build/Products/Release/Peekaboo.app
PREFIX := /Applications

.PHONY: build test check app install run

build:
	$(XCODEBUILD) -configuration Debug build

test:
	$(XCODEBUILD) -configuration Debug test

check: test

app:
	$(XCODEBUILD) -configuration Release build
	codesign --verify --strict "$(APP)"

install: app
	@test -d "$(PREFIX)" || { echo "$(PREFIX) does not exist; set PREFIX to somewhere that does"; exit 1; }
	@test -w "$(PREFIX)" || { echo "$(PREFIX) is not writable; rerun as root or set PREFIX"; exit 1; }
	rm -rf "$(PREFIX)/Peekaboo.app"
	cp -R "$(APP)" "$(PREFIX)/Peekaboo.app"

run: build
	open .build/Build/Products/Debug/Peekaboo.app
