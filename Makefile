SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help run run-probe build-local run-local test-local

help:
	@printf '%s\n' \
	  'make run         Build every Swift library and launch Amcam Imaging' \
	  'make run-probe   Build and run the Amcam camera diagnostic locally' \
	  'make build-local Build every Swift library and the imaging executable' \
	  'make run-local   Alias for make run' \
	  'make test-local  Run every Swift package test suite locally'

run:
	@bash scripts/build-and-run-macos.sh

run-probe:
	swift run --package-path swift/Packages/AmcamGenTL amcam-camera-probe $(PROBE_ARGS)

build-local:
	@BUILD_ONLY=1 bash scripts/build-and-run-macos.sh

run-local: run

test-local:
	@set -e; \
	for package in \
	  swift/Packages/GenTLABI \
	  swift/Packages/GenTLAPI \
	  swift/Packages/GenTLNative \
	  swift/Packages/AmcamCameraModel \
	  swift/Packages/AmcamImagingCore \
	  swift/Packages/AmcamImagingApplicationCore \
  swift/Packages/AmcamImagingGenTLAdapter \
	  swift/Packages/AmcamGenTL \
	  swift/Packages/GenTLRouter; do \
	  echo "==> swift test: $$package"; \
	  swift test --package-path "$$package"; \
	done
