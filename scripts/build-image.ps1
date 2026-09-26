<#
.SYNOPSIS
    Builds the internal-initializr image from pinned upstream sources and loads it into KinD.

.DESCRIPTION
    1. Clones spring-io/initializr and spring-io/start.spring.io into upstream/ (gitignored) and
       checks out the commits in upstream.lock.
    2. Re-creates the local branch `internal` in start.spring.io at the pinned commit and applies
       patches/start.spring.io/*.patch with `git am`. Our changes live in this repo as patches, so
       the nested clone can be thrown away at any time.
    3. Builds and installs initializr. start.spring.io depends on a SNAPSHOT of it; building it
       from the pinned commit avoids depending on repo.spring.io/snapshot, whose snapshots move
       and expire. The start.spring.io build then runs with -nsu so Maven keeps the local one.
    4. Builds start.spring.io (start-client, the web UI, then start-site) and copies
       start-site-exec.jar to build/.
    5. docker build, kind load, and a rollout restart if the Deployment already exists.

    Uses the host's `mvn`, not upstream's mvnw: mvnw ignores Maven's conf/settings.xml, which is
    where this machine points Maven at the local Nexus. start-client's frontend-maven-plugin
    downloads Node and Yarn and runs `yarn install`, which needs internet access or an npm proxy.

.EXAMPLE
    ./scripts/build-image.ps1
    ./scripts/build-image.ps1 -Tag 0.2.0 -RunTests
    ./scripts/build-image.ps1 -SkipUpstreamBuild     # only re-package the image from build/
#>
param(
    [string]$Tag = "0.1.0",
    [string]$ClusterName = "claude-local",
    [string]$ImageName = "internal-initializr",
    [string]$Namespace = "internal-initializr",
    [switch]$RunTests,
    [switch]$SkipUpstreamBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

function Invoke-Checked([string]$what, [scriptblock]$cmd) {
    & $cmd
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" }
}

function Read-Lock {
    $lock = @{}
    Get-Content (Join-Path $root "upstream.lock") | Where-Object { $_ -match '^\s*[A-Z_]+=' } | ForEach-Object {
        $k, $v = $_ -split '=', 2
        $lock[$k.Trim()] = $v.Trim()
    }
    return $lock
}

function Sync-Upstream([string]$dir, [string]$repo, [string]$commit) {
    if (-not (Test-Path (Join-Path $dir ".git"))) {
        Write-Host "==> Cloning $repo" -ForegroundColor Cyan
        Invoke-Checked "git clone" { git clone --quiet $repo $dir }
    }
    Invoke-Checked "git fetch" { git -C $dir fetch --quiet origin }
    # --force: throw away anything left in the working tree. Local edits here are not kept; changes
    # belong in patches/.
    Invoke-Checked "git checkout" { git -C $dir checkout --quiet --force $commit }
}

try
{
    if (-not $SkipUpstreamBuild) {
        $lock = Read-Lock
        $initializr = Join-Path $root "upstream/initializr"
        $start = Join-Path $root "upstream/start.spring.io"

        Sync-Upstream $initializr $lock.INITIALIZR_REPO $lock.INITIALIZR_COMMIT
        Sync-Upstream $start $lock.START_SPRING_IO_REPO $lock.START_SPRING_IO_COMMIT

        Write-Host "==> Applying patches on branch 'internal'" -ForegroundColor Cyan
        Invoke-Checked "git branch" { git -C $start checkout --quiet -B internal $lock.START_SPRING_IO_COMMIT }
        $patches = Get-ChildItem (Join-Path $root "patches/start.spring.io") -Filter *.patch | Sort-Object Name
        foreach ($p in $patches) {
            Write-Host "    $($p.Name)"
            Invoke-Checked "git am $($p.Name)" {
                git -C $start -c user.name="internal-initializr" -c user.email="build@localhost" am --quiet --3way $p.FullName
            }
        }

        Write-Host "==> Building initializr (library) at $($lock.INITIALIZR_COMMIT.Substring(0,8))" -ForegroundColor Cyan
        # docs and the sample service are not needed and are the slowest modules.
        Invoke-Checked "initializr build" {
            mvn -B -f "$initializr/pom.xml" -pl '!initializr-docs,!initializr-service-sample' install -DskipTests
        }

        Write-Host "==> Building start.spring.io at $($lock.START_SPRING_IO_COMMIT.Substring(0,8))" -ForegroundColor Cyan
        # disable.checks: upstream's javaformat and checkstyle validation; our patch is not run
        # through their formatter. -nsu: keep the initializr SNAPSHOT just installed locally.
        $mvnArgs = @("-B", "-nsu", "-f", "$start/pom.xml", "-Ddisable.checks=true", "clean", "install")
        if (-not $RunTests) { $mvnArgs += "-DskipTests" }
        Invoke-Checked "start.spring.io build" { mvn @mvnArgs }

        New-Item -ItemType Directory -Force -Path (Join-Path $root "build") | Out-Null
        Copy-Item "$start/start-site/target/start-site-exec.jar" (Join-Path $root "build/start-site-exec.jar") -Force
    }
    elseif (-not (Test-Path (Join-Path $root "build/start-site-exec.jar"))) {
        throw "build/start-site-exec.jar does not exist; run without -SkipUpstreamBuild first"
    }

    Write-Host "==> Building image $ImageName`:$Tag" -ForegroundColor Cyan
    Invoke-Checked "docker build" { docker build -t "$ImageName`:$Tag" . }

    Write-Host "==> Loading it into KinD cluster '$ClusterName'" -ForegroundColor Cyan
    Invoke-Checked "kind load" { kind load docker-image "$ImageName`:$Tag" --name $ClusterName }

    # Same tag, new image: Kubernetes will not notice on its own.
    # --ignore-not-found keeps "not deployed yet" off stderr, which $ErrorActionPreference = Stop
    # would otherwise turn into a failure on the first build.
    $deployment = kubectl get deployment $ImageName -n $Namespace --ignore-not-found -o name
    if ($LASTEXITCODE -ne 0) { throw "kubectl get deployment failed (exit $LASTEXITCODE)" }
    if ($deployment) {
        Write-Host "==> Restarting the running Deployment" -ForegroundColor Cyan
        Invoke-Checked "rollout restart" { kubectl rollout restart "deployment/$ImageName" -n $Namespace }
    }
    else {
        Write-Host "Not deployed yet. Next: ./scripts/deploy.ps1" -ForegroundColor Green
    }
}
finally
{
    Pop-Location
}
