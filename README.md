# internal-initializr

The start.spring.io site, forked and hosted in the local KinD cluster, offering only what the
local Nexus holds. Browse to `http://initializr.claude.local`, pick options, click Generate: the
project that downloads builds against Nexus alone, Maven wrapper included.

## Prerequisites

- The `claude-local` KinD cluster with ingress-nginx, from `Projects/ClaudePractice`
  (`k8s/kind-config.yaml`; see that project's CLAUDE.md for the ingress install).
- On the host: JDK 17+, Maven (with the Nexus mirror in its `conf/settings.xml`), git, Docker,
  kind, kubectl, helm.
- Internet access for the first build: git clones from GitHub, and start-client's build downloads
  Node, Yarn and npm packages.
- Hosts file entry: `127.0.0.1 initializr.claude.local`

## Build, deploy, verify

```powershell
./scripts/build-image.ps1                  # clones + pins upstream, applies patches, builds, kind load
./scripts/deploy.ps1                       # helm upgrade --install into namespace internal-initializr
./scripts/verify-generated-projects.ps1    # generates projects and builds them through Nexus only
```

Before the first deploy, confirm the Nexus repository URL in
`charts/internal-initializr/values.yaml` (`nexus.mavenRepositoryUrl`); `maven-public` is only the
Nexus default name.

## Changing things

| Change | Where | Then |
|---|---|---|
| Boot versions, starters, Java versions | `charts/internal-initializr/files/initializr-menu.yml` | `deploy.ps1`, `verify-generated-projects.ps1` |
| Nexus URL for generated wrappers | `values.yaml` or `deploy.ps1 -NexusUrl` | `deploy.ps1` |
| Site code | commit on branch `internal` in `upstream/start.spring.io`, `git format-patch` into `patches/start.spring.io/` | `build-image.ps1` |
| Upstream version | both commits in `upstream.lock`; re-copy menu entries | `build-image.ps1`, `deploy.ps1`, verify |

## What is changed from upstream

- **Menu** (config, no code): Maven projects only, Java only, Boot 4.1.1 and 4.0.8, a short list of
  approved starters, and the api.spring.io version lookup disabled.
- **Maven wrapper** (patch 0001): generated `maven-wrapper.properties` downloads Maven from
  `internal.maven-wrapper.repository-url` instead of `repo.maven.apache.org`, keeping the Maven
  version upstream chose.

Upstream: [spring-io/start.spring.io](https://github.com/spring-io/start.spring.io) and
[spring-io/initializr](https://github.com/spring-io/initializr), Apache 2.0.
