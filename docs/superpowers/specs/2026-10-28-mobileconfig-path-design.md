# MobileConfig override path alignment

The user wants the MobileConfig integration corrected using the supplied IPA as
the authority. The current fallback resolver checks Documents first, selects by
JSON-file existence and invents a bundle-dependent location when neither native
directory exists. The 584.1 selector at Shared 0x154b80 instead checks the
container's mobileconfig path before Documents/mobileconfig and returns an empty
path if neither exists. A live getOverridesTablePath remains authoritative.

Use that native directory order in the existing resolver. Preserve app-group
priority, resolve an empty preferred directory before a secondary JSON file,
return nil when the native layout is absent, and leave directory creation to the
existing explicit ensure operation after a path has been resolved. Do not delete,
copy or merge duplicate override files automatically.

Considered approaches: observing the actual native path is strongest and already
implemented; the corrected directory fallback supports the period before that
observation. Synchronizing every discovered JSON file would conceal context
differences and is rejected. This fixes which file the editor addresses; it does
not establish server authorization or bypass the importer cache.

Tests execute the production resolver body against real temporary filesystem
trees, replacing only entitlement lookup and live-object discovery. They must
reproduce root/Documents collisions and the directory-without-JSON case.
