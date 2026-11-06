#!/usr/bin/env python3
"""Set the Android app minimum SDK required by the Xray runtime."""
from pathlib import Path
import re
import sys

app_dir = Path(sys.argv[1]).resolve()
candidates = [
    app_dir / "android" / "app" / "build.gradle.kts",
    app_dir / "android" / "app" / "build.gradle",
]
gradle = next((path for path in candidates if path.is_file()), None)
if gradle is None:
    raise SystemExit(f"Android app Gradle file not found under {app_dir}")

source = gradle.read_text(encoding="utf-8")
if gradle.name.endswith(".kts"):
    updated, count = re.subn(
        r"minSdk\\s*=\\s*(?:flutter\\.minSdkVersion|\\d+)",
        "minSdk = 23",
        source,
        count=1,
    )
else:
    updated, count = re.subn(
        r"minSdkVersion\\s+(?:flutter\\.minSdkVersion|\\d+)",
        "minSdkVersion 23",
        source,
        count=1,
    )
if count == 0:
    raise SystemExit(f"Could not locate minSdk declaration in {gradle}")
gradle.write_text(updated, encoding="utf-8")
print(f"Android minSdk set to 23 in {gradle}")
