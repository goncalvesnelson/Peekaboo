XCODEBUILD := xcodebuild -project AppToggle.xcodeproj -scheme AppToggle -destination 'platform=macOS,arch=$(shell uname -m)' -derivedDataPath .build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES

.PHONY: build test check run

build:
	$(XCODEBUILD) build

test:
	$(XCODEBUILD) test

check: test

run: build
	open .build/Build/Products/Debug/AppToggle.app
