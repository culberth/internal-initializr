# internal-initializr

A fork of start.spring.io hosted in the local KinD cluster (`claude-local`) at
`http://initializr.claude.local`: the same web page developers know, with a menu limited to the
Spring Boot versions and starters the local Nexus holds, and generated projects whose Maven
wrapper downloads Maven from that Nexus. It is the rehearsal for running the same site on an
offline network. Status and history: `memory.md`. Plan and decisions: `docs/plan.md`.

## Layout

This root repo is ours. Upstream code is never committed here.

- `upstream.lock` — the two upstream repos and pinned commits. They move together (see the file).
- `upstream/` — gitignored clones of `spring-io/initializr` and `spring-io/start.spring.io`,
  recreated by `scripts/build-image.ps1`. Do not edit files in it: the script checks out with
  `--force` and discards local changes.
- `patches/start.spring.io/*.patch` — our code changes to upstream, applied with `git am` onto a
  fresh local branch `internal` on every build. To change code: edit in `upstream/start.spring.io`
  on branch `internal`, commit, then `git format-patch` the commits back into this folder.
- `charts/internal-initializr/files/initializr-menu.yml` — the menu (Boot versions, starters,
  Java versions, build types). Mounted as `/config/application.yml`; every list in it replaces
  upstream's list wholesale.
- `Dockerfile` — runtime-only image around `build/start-site-exec.jar`.
- `scripts/` — `build-image.ps1` (upstream → jar → image → `kind load`), `deploy.ps1` (helm),
  `verify-generated-projects.ps1` (menu ↔ Nexus check).

## Commands (PowerShell, from the repo root)

- Build and load the image: `./scripts/build-image.ps1` (`-RunTests` to run upstream's tests,
  `-SkipUpstreamBuild` to re-package the existing jar)
- Install or upgrade: `./scripts/deploy.ps1` (`-NexusUrl ...` to override the wrapper repo)
- Verify: `./scripts/verify-generated-projects.ps1` (`-PerDependency`, `-BootVersion 4.0.8`)
- Menu-only change: edit the menu file, then `./scripts/deploy.ps1`. No rebuild.
- Hosts file: `127.0.0.1 initializr.claude.local`

## Rules that are not obvious

1. **Only list what Nexus holds.** The site never checks that a generated pom resolves. Add a Boot
   version or starter to the menu only after `verify-generated-projects.ps1` passes for it.
2. **Upstream supports Boot 4.x only.** Its compatibility ranges start at 4.0.0 and its metadata
   strategy filters out older versions. Do not add 3.x Boot versions to the menu.
3. **Use the host `mvn`, never upstream's `mvnw`.** Maven's own `conf/settings.xml` points at the
   local Nexus on `localhost:8081`; the wrapper's Maven does not read it. Same reason the image is
   built from a host-built jar (see artemis-browser's CLAUDE.md).
4. **Build initializr before start.spring.io, and keep `-nsu`.** start.spring.io depends on an
   initializr SNAPSHOT. Without the local build and `-nsu`, Maven fetches whatever snapshot
   repo.spring.io has today, which may not match the pinned start.spring.io commit.
5. **`initializr.env.spring-boot-metadata-url: ''` must stay.** Otherwise the site calls
   api.spring.io at startup and on refresh; offline that fails and, online, it replaces our
   Boot version list with spring.io's.
6. **Rebuilding on the same tag restarts nothing** unless the Deployment is restarted;
   `build-image.ps1` does it when the Deployment exists.

## Conventions

Same as the other projects here: global rules in Cowork's Global Instructions, deliverables in
`ClaudeOutput/internal-initializr/`, never push without asking.
