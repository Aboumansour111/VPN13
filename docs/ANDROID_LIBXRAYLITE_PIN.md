# AndroidLibXrayLite pinned artifact

- Upstream project: https://github.com/2dust/AndroidLibXrayLite
- Release: v26.10.31 (published 2026-11-01)
- Artifact: `libv2ray.aar`
- Release asset size: 60,031,471 bytes
- SHA-256: `2efdf731b1ed624eb1cb0d5a4d0aa95c0672e89f9702226d1ba2dc90308630b6`
- Release URL: https://github.com/2dust/AndroidLibXrayLite/releases/download/v26.10.31/libv2ray.aar

The AAR should be downloaded into `client/android/app/libs/libv2ray.aar` (not committed to this repository). Gradle must include it as a local AAR dependency. This avoids a 60 MB binary in Git history and keeps the exact artifact reproducible.

Do not use a floating/latest URL in builds. Verify the SHA-256 before Gradle uses it.
