# Mobile Lab — Facebook 584.1

FBTweak's Mobile Lab switch is ON by default (`fbt_mobile_lab_enabled`). It adds
`LAB_IS_ACTIVE=1` at the beginning of the tweak's constructor after prefs
registration and before installing any FBTweak hooks. It does not hook
`FBMobileLabIsActive`, write signed `__TEXT`, or add Tigon/QE interception.

Implementation: `setenv("LAB_IS_ACTIVE", "1", 0)` preserves any inherited
environment value. The native function checks key presence rather than value.

Switch OFF disables the tweak's assignment on the **next process launch**.
It cannot erase an environment variable supplied by the parent or another
library. The native function caches its first result, and Foundation may
cache its environment earlier still. Restart Facebook fully after switching.
The sideload initializer order is not guaranteed: validation on-device is
required to show that the key was set before the host's first check.

Existing crash containment is unchanged: no `MSHookFunction`, no C++ vtable
or callback injection, no invasive QE hooks, no runtime-browser restoration
during the dyld constructor. This is not Employee backend authorization.

Validation: `python3 -m unittest discover -s tests -p 'test_mobile_lab_bootstrap.py' -v`
