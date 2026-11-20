SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help run run-probe build-local run-local test-local

help:
	@printf '%s\n' \
	  'make run         Download and launch the latest hosted macOS imaging app' \
	  'make run-probe   Download and run the latest hosted camera diagnostic probe' \
	  'make build-local Build the imaging app with the local Swift toolchain (Xcode required)' \
	  'make run-local   Build and launch the imaging app locally (Xcode required)' \
	  'make test-local  Run every Swift package test suite locally (Xcode required)'

run:
	@bash scripts/run-macos-artifact.sh app

run-probe:
	@bash scripts/run-macos-artifact.sh probe

build-local:
	swift build --package-path swift/Apps/AmcamImagingApp --product amcam-imaging

run-local:
	swift run --package-path swift/Apps/AmcamImagingApp amcam-imaging

test-local:
	@set -e; \
	for package in \
	  swift/Packages/GenTLABI \
	  swift/Packages/GenTLAPI \
	  swift/Packages/GenTLNative \
	  swift/Packages/AmcamCameraModel \
	  swift/Packages/AmcamGenTL \
	  swift/Packages/GenTLRouter; do \
	  echo "==> swift test: $$package"; \
	  swift test --package-path "$$package"; \
	done
