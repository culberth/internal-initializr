# Plan

Goal: a start.spring.io equivalent in the KinD cluster whose menu matches what the local Nexus
holds, as the rehearsal for the same site on an offline network.

## Phases

| # | Phase | Done when |
|---|---|---|
| 1 | Upstream builds on the host | `build-image.ps1` produces `build/start-site-exec.jar` |
| 2 | Site runs in KinD | `http://initializr.claude.local` shows the page; `/actuator/health` UP |
| 3 | Offline changes | No api.spring.io call in the pod log; menu shows only our list; a generated project's wrapper points at Nexus |
| 4 | Verified against Nexus | `verify-generated-projects.ps1` passes for 4.1.1 (and 4.0.8) |

## Decisions

- **Fork start.spring.io, not the bare initializr libraries** — the goal is the web page, which only
  start.spring.io has.
- **Nested clones + patches, not a GitHub fork** — nothing on the GitHub account; our changes are
  versioned here as patch files; the clone is disposable.
- **Menu as a ConfigMap overlay, not an edited application.yml** — menu changes are a `helm upgrade`,
  not a rebuild, and upstream's 2,400-line file stays untouched, which keeps upstream bumps clean.
- **Wrapper URL via a ProjectContributor patch, not a classpath override of the wrapper files** — the
  override would mean copying the wrapper scripts and freezing the Maven version; the contributor
  rewrites only the URL prefix after upstream writes the file.
- **Build initializr locally** — start.spring.io pins an initializr SNAPSHOT; a local build from a
  pinned commit is reproducible, repo.spring.io/snapshot is not.
- **Plain HTTP, one replica** — the site is stateless and holds no secrets.

## Open questions

- Which Nexus repository name generated wrappers should use (`maven-public` is assumed).
- Whether upstream's Azure Key Vault starter tries anything at startup without configuration
  (expected: no; check the first pod log).
- Whether start-client's Node/Yarn downloads work from the host as-is, or need a Nexus npm proxy
  (they will on the offline network).
- The approved starter list is a starting point drawn from what the other projects here use;
  adjust it.
