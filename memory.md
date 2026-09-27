# internal-initializr — memory

## Status

- 2026-09-26: Project scaffolded (plan, chart, scripts, patch 0001, menu). Nothing built or deployed
  yet. The Maven build could not be run from Cowork's sandbox (no access to Maven Central or to the
  host's Nexus), and the patch has not been compiled. Phase 1 is next: `./scripts/build-image.ps1`.
- 2026-09-26: Phase 1 build passed on the host: initializr d445a056 and start.spring.io 29903a3f
  (with patch 0001) compiled, image `internal-initializr:0.1.0` loaded into all three
  `claude-local` nodes.
- 2026-09-26: Deployed (helm revision 1) at http://initializr.claude.local; hosts entry added.
  `verify-generated-projects.ps1` passed for Boot 4.1.1 and 4.0.8 (all 17 starters, one combined
  project each; wrapper and build both through Nexus). Not yet run: `-PerDependency`, `-RunTests`.
- 2026-09-27: Optional HTTPS added (Chrome showed "Not Secure" on plain HTTP): `ingress.tls.secretName`,
  `new-tls-secret.ps1` (mkcert), `deploy.ps1` enables TLS when secret `internal-initializr-tls`
  exists, and `SERVER_FORWARD_HEADERS_STRATEGY=native` so metadata links say https behind the
  ingress (checked via port-forward with X-Forwarded-Proto). KinD already maps host 443.
- 2026-09-27: HTTPS live at https://initializr.claude.local. User installed mkcert 1.4.4 and ran
  `mkcert -install` (CA in the Windows store and in JAVA_HOME's cacerts). Cert expires 2028-12-27.
  HTTP answers 308 to HTTPS; `verify-generated-projects.ps1` (now defaulting to https) passed.

## Verified facts (from reading upstream source at the pinned commits)

- `initializr.env.spring-boot-metadata-url` defaults to https://api.spring.io/projects/spring-boot/releases;
  `SpringIoInitializrMetadataUpdateStrategy` skips the fetch when it is blank.
- start.spring.io's `StartInitializrMetadataUpdateStrategy` filters fetched versions below 4.0.0.
- Maven wrapper template: `initializr-generator-spring/src/main/resources/maven/3/wrapper/.mvn/wrapper/maven-wrapper.properties`,
  wrapper 3.3.4, `distributionType=only-script`, Maven 3.9.16 from repo.maven.apache.org.
- `ProjectGenerationContext` has the application context as parent (`ProjectGenerationInvoker`),
  so `Environment` injection in a `@ProjectGenerationConfiguration` sees application properties.
- start.spring.io 29903a3 builds on Boot 4.1.0 parent, needs initializr 0.25.0-SNAPSHOT, and
  declares repo.spring.io/snapshot. start-client uses frontend-maven-plugin (Node v24.16.0, Yarn
  1.22.22). Google Tag Manager is injected only when GOOGLE_TAGMANAGER_ID is set at build time.
- Upstream checks are skipped with `-Ddisable.checks=true`.

## Traps

- **Maven Central answers 403 (Cloudflare) from this network** (seen 2026-09-26), so the Nexus
  `maven-central` proxy served only what it had cached and 404'd the rest. Fix applied: its remote
  storage now points at Google's mirror, `https://maven-central.storage-download.googleapis.com/maven2/`,
  plus Invalidate cache. After a Nexus 404, also delete the `*.lastUpdated` markers in Maven's local
  repo, which is `P:\maven_local_repositories\.m2\spring-boot` (not `~/.m2`).
- **Windows PowerShell 5.1 + `$ErrorActionPreference = "Stop"`: native stderr becomes fatal once
  redirected.** `docker build` writes progress to stderr, so running `build-image.ps1 *>&1 | Tee-Object`
  fails at the image step. Run it without redirecting. The script's own Deployment check had the same
  bug (`kubectl ... *> $null` on a missing namespace); it now uses `--ignore-not-found`.
