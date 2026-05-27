# FBTweaks

Base Theos tweak for Facebook iOS.

This repository is intentionally clean and minimal. It was adapted from the buildable WATweaks/Theos base, but the runtime logic is Facebook-specific and starts empty.

## Build

```sh
./build.sh
```

The GitHub Actions workflow builds a rootless package using Theos and a vendored fishhook copy.
