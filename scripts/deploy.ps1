<#
.SYNOPSIS
    Installs or upgrades the internal-initializr chart on the local KinD cluster.

.DESCRIPTION
    Assumes the claude-local cluster and ingress-nginx from the ClaudePractice project are already
    running, and that build-image.ps1 has loaded the image. Menu-only changes
    (charts/internal-initializr/files/initializr-menu.yml) need only this script, not a rebuild:
    the Deployment carries a checksum of the menu, so the pod rolls.

.EXAMPLE
    ./scripts/deploy.ps1
    ./scripts/deploy.ps1 -NexusUrl http://localhost:8081/repository/maven-central
#>
param(
    [string]$Release = "internal-initializr",
    [string]$Namespace = "internal-initializr",
    [string]$NexusUrl = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$chart = Join-Path $root "charts/internal-initializr"

helm lint $chart
if ($LASTEXITCODE -ne 0) { throw "helm lint failed" }

$helmArgs = @("upgrade", "--install", $Release, $chart, "-n", $Namespace, "--create-namespace", "--wait", "--timeout", "5m")
if ($NexusUrl) { $helmArgs += @("--set", "nexus.mavenRepositoryUrl=$NexusUrl") }
helm @helmArgs
if ($LASTEXITCODE -ne 0) { throw "helm upgrade failed" }
