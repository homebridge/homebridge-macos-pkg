.PHONY: help staging pkg dmg container-staging local clean

help:
	@echo "Targets:"
	@echo "  local              - One-command local build (staging + pkg + dmg)"
	@echo "  staging            - Prepare staging tarball (build/homebridge-staging.tar.gz)"
	@echo "  pkg                - Build macOS .pkg using Packages app (if available)"
	@echo "  dmg                - Create a .dmg containing the app bundles"
	@echo "  container-staging  - Build staging tarball inside Docker container"
	@echo "  clean              - Remove build artifacts"

local:
	@bash build-local.sh

staging:
	@bash build.sh --staging-only

pkg:
	@bash build.sh

dmg:
	@bash scripts/make-dmg.sh

container-staging:
	@bash scripts/container-build.sh

clean:
	rm -rf build
