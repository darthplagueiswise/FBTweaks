# FBTweaks

Base Theos tweak for Facebook iOS.

This repository was initialized from the buildable WATweaks/Theos base and trimmed to a clean Facebook-oriented skeleton:

- Theos tweak layout
- Facebook bundle filter: `com.facebook.Facebook`
- vendored `fishhook` module path in `modules/fishhook`
- GitHub Actions build workflow
- `build.sh` / `build-fast.sh`
- minimal diagnostic gesture: two-finger triple tap shows a basic FBTweaks alert

Add future hook modules under `src/Hooks/` and keep `src/Tweak.x` as a light bootstrap/orchestrator.

## Build

```sh
export THEOS=/path/to/theos
bash ./build.sh
```

## Validate

```sh
python3 scripts/fbt_validate_sources.py
```
