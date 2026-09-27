<#
.SYNOPSIS
    Installs or upgrades the internal-initializr chart on the local KinD cluster.

.DESCRIPTION
    Assumes the claude-local cluster and ingress-nginx from the ClaudePractice project are already
    running, and that build-image.ps1 has loaded the image. Menu-only changes
    (charts/internal-initializr/files/initializr-menu.yml) need only this script, not a rebuild:
    the Deployment carries a checksum of the menu, so the pod rolls.

    HTTPS: if the secret -TlsSecret exists in the namespace (scripts/new-tls-secret.ps1 makes it),
    the ingress serves HTTPS with it and redirects HTTP; otherwise the site is plain HTTP.

.EXAMPLE
    ./scripts/deploy.ps1
    ./scripts/deploy.ps1 -NexusUrl http://localhost:8081/repository/maven-central
#>
param(
    [string]$Release = "internal-initializr",
    [string]$Namespace = "internal-initializr",
    [string]$NexusUrl = "",
    [string]$TlsSecret = "internal-initializr-tls"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$chart = Join-Path $root "charts/internal-initializr"

helm lint $chart
if ($LASTEXITCODE -ne 0) { throw "helm lint failed" }

$helmArgs = @("upgrade", "--install", $Release, $chart, "-n", $Namespace, "--create-namespace", "--wait", "--timeout", "5m")
if ($NexusUrl) { $helmArgs += @("--set", "nexus.mavenRepositoryUrl=$NexusUrl") }
# --ignore-not-found: a missing secret is empty output. No stderr redirect: in Windows PowerShell
# 5.1 with Stop, redirected native stderr is fatal (see memory.md, Traps).
$found = kubectl -n $Namespace get secret $TlsSecret --ignore-not-found -o name
if ($found) {
    Write-Host "TLS: using secret $Namespace/$TlsSecret (HTTPS, HTTP redirects)"
    $helmArgs += @("--set", "ingress.tls.secretName=$TlsSecret")
} else {
    Write-Host "TLS: no secret $Namespace/$TlsSecret, serving plain HTTP (see scripts/new-tls-secret.ps1)"
}
helm @helmArgs
if ($LASTEXITCODE -ne 0) { throw "helm upgrade failed" }
