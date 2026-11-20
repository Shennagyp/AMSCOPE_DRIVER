# Vendor SDK layout

Place vendor runtime libraries under a vendor-specific directory. The application
build copies this tree into the app bundle and signs packaged macOS dynamic
libraries before signing the app itself.

Current AmScope SDK location:

```text
vendor/
  amscope/
    macos/
      arm64/
        libamcam.dylib
        <any sibling runtime dependencies>
      x86_64/
        libamcam.dylib
        <any sibling runtime dependencies>
      universal/
        libamcam.dylib
        <any sibling runtime dependencies>
  <other-vendor>/
    ...
```

Use the architecture matching the process. A universal binary may be placed in
`universal/`. Keep all vendor-supplied sibling dependencies in the same
architecture directory so their own `@loader_path` references remain valid.

Do not commit proprietary SDK binaries unless the vendor license explicitly
permits redistribution. For local development, obtain the SDK from the vendor
and place it here. The app does not provide a file picker for native libraries.
