# FBTweaks — Bloks Lab Live Trace (experimental, read-only)

## Purpose
Instrument inside an already-injected, re-signed Facebook process (no Frida server, no jailbreak assumed). This is NOT a replacement for the Facebook Whitehat HTTPS inspector.

Menu: FBTweaks → Diagnóstico / Tools → Bloks Lab · Live Trace.

### Captured (opt-in)
- Actual Boolean result of -[FBReachabilityAnnouncer connectedToVPN], only when the app calls it. Repeated unchanged values are suppressed.
- Three Boolean arguments of BKBloksLabDeeplinkHelper processDeeplinkWith:...:passPrototypeShortcode:useInternalNetworkCheck:isEmployee:... if the Objective-C runtime method exists with the expected ABI.
- Recognized Boolean setter calls in BKBloksLabLandingScreenQueryBuilder and ...BridgedBuilder if exposed to the Objective-C runtime; best effort, some Swift/C++ flows don't use ObjC setters.
- Local timestamps, class and selector names. No account IDs, tokens, cookies, request bodies, certificates, or authorization headers.

No argument or return value is modified. No fake employee/VPN eligibility is implemented.

### How to test
1. Inject FBTweaks into the signed Facebook IPA using the same process that works for your Allflexing.
2. Open Bloks Lab Live Trace, switch on Captura observacional, then tap Revalidar hooks.
3. Read the status: hook installed versus class not loaded / selector or ABI unavailable. If unavailable, open Bloks Lab and tap Revalidar hooks again.
4. Reopen Bloks Lab. Tap Marcar for a timestamp-only marker before a repro.
5. Filter VPN / Bloks, then Exportar JSONL. With Filza, browse the sideloaded Facebook application container under Documents/FBTweaksDiagnostics/BloksLabTrace.jsonl.
6. For cold-start capture, leave it enabled and fully restart the application. The enabled setting persists; retries install as classes load.
7. Turn capture off when finished. Limpar deletes the current capture file.

### Whitehat vs on-device trace
The screenshots show Allow user-installed certificates and Do not use TLS 1.3 (Fizz) enabled. Another Whitehat page has SSL Pinning Bypass off, and says no proxy CA imported.

For HTTPS, run Burp/Charles/mitmproxy, configure a Wi-Fi HTTP proxy and install its PUBLIC CA certificate on iOS. Trust that CA in iOS Certificate Trust Settings, import it into Whitehat if the screen permits, enable the bypass as needed and restart the app.

Whitehat reveals proxyable HTTP(S) requests/responses; Live Trace reveals observed native boolean values. Neither grants internal entitlements, employee status, or VPN access.

### Limitations and safety
- Uses MSHookMessageEx already present in FBTweaks, without a new injection engine.
- Detects Objective-C selectors dynamically and checks argument types. No hardcoded offsets from a mismatched IPA.
- Swift/C++-only methods, methods loaded late, and other non-ObjC call paths may be invisible.
- The VPN getter might NOT feed the Bloks Lab context; its result is not proof of what dng(is_on_vpn) receives.
- Default capture is off; local log rotates at 4 MiB. Captured data stays within the current app container.
- Not compiled with an Apple iPhoneOS SDK or tested on an iOS 27 device here. Validate in your Theos/iOS build environment before deploying.

Run python3 scripts/fbt_validate_bloks_trace.py for static wiring checks.
