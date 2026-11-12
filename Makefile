.PHONY: build release clean

VERSION ?=

build:
	xcodebuild -project OllamaUsageTracker.xcodeproj -scheme OllamaUsageTracker -destination 'platform=macOS' build

release:
	./scripts/make_release.sh $(VERSION)

clean:
	rm -rf build dist
