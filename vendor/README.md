# Vendor SDK directory

Vendor binaries are deployment inputs and are not selected from the UI. Keep
each vendor isolated under its own directory:

```text
vendor/
  amcam/
    macos/
      libamcam.dylib
      <sibling runtime dependencies>
  <another-vendor>/
    macos/
      <vendor runtime libraries>
```

The macOS build copies this tree into:

```text
<application>.app/Contents/Frameworks/Vendors/<vendor>/...
```

For AmScope, the backend looks first in the application bundle at
`Contents/Frameworks/Vendors/amcam/macos/libamcam.dylib`. It then checks the
per-user and machine-wide SDK installation locations documented in
`swift/Packages/AmcamGenTL`.

The build also accepts `AMCAM_SDK_SOURCE=/absolute/path/to/libamcam.dylib`.
It validates that the SDK contains every architecture used by the application,
copies it into the app bundle, and signs the bundled copy. The vendor source
file is not modified. Set `REQUIRE_AMCAM_SDK=1` to fail packaging when the
AmScope SDK is missing; without it, the app can launch with that provider
unavailable.

The local build uses an ad-hoc signature for the copied native libraries and
application bundle. This is a development signing step, not a distribution
trust solution. Distribution builds must use a Developer ID identity to sign
the final app bundle and complete Apple's notarization process.

Do not commit proprietary SDK binaries unless the vendor license explicitly
permits redistribution.
