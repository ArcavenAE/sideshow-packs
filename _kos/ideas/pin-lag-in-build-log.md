# idea: print the pin-lag report in the build log

**Date:** 2026-09-27
**From:** the Opportunities note on sideshow-packs#35 (aae-orc-soh8q)

`scripts/pin-lag.sh` reports, per external module, the upstream tags newer
than the pin a pack was built with. Today someone has to run it. A warn-only
step in `build-pack.yml` after the build could print the same report, so every
build log shows how far the as-of composition already trails upstream on the
day it was built.

Held back from #35 because it adds network calls (`git ls-remote` per module)
to the build path. That cost is small, but it is a new failure surface on the
release run, and `pin-lag.sh` exits 0 on unreachable upstreams by design, so
the step would never block a build.

Not a commitment; no bd ticket.
