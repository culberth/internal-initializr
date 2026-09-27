<#
.SYNOPSIS
    Creates the TLS secret that serves the site over HTTPS, from a certificate issued by mkcert.

.DESCRIPTION
    One-time prerequisite, done by you (not this script) because it changes what Windows trusts:
        winget install FiloSottile.mkcert
        mkcert -install
    `mkcert -install` puts mkcert's local CA into the Windows certificate store, which Chrome, Edge
    and PowerShell's Invoke-WebRequest use. Firefox keeps its own store; mkcert adds to it only if
    certutil is available.

    This script issues a certificate for the host (the CA's key never leaves your profile), then
    creates or replaces the kubernetes.io/tls Secret. Run ./scripts/deploy.ps1 afterwards: it sees
    the secret and switches the ingress to HTTPS. Re-running is safe; the pod does not restart, the
    ingress controller picks up the new certificate on its own.

    The key and certificate are written to .tls/ (gitignored) and nowhere else.

.EXAMPLE
    ./scripts/new-tls-secret.ps1
#>
param(
    [string]$HostName = "initializr.claude.local",
    [string]$Namespace = "internal-initializr",
    [string]$SecretName = "internal-initializr-tls"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command mkcert -ErrorAction SilentlyContinue)) {
    throw "mkcert not found. Install it and trust its CA first: winget install FiloSottile.mkcert; mkcert -install (then open a new terminal)"
}
$caRoot = (mkcert -CAROOT).Trim()
if (-not (Test-Path (Join-Path $caRoot "rootCA.pem"))) {
    throw "mkcert has no local CA yet. Run: mkcert -install"
}

$dir = Join-Path $root ".tls"
New-Item -ItemType Directory -Force $dir | Out-Null
$cert = Join-Path $dir "$HostName.pem"
$key = Join-Path $dir "$HostName-key.pem"

mkcert -cert-file $cert -key-file $key $HostName
if ($LASTEXITCODE -ne 0) { throw "mkcert failed" }

# Create only when missing: `kubectl apply` on the Helm-created namespace warns about annotations.
if (-not (kubectl get namespace $Namespace --ignore-not-found -o name)) {
    kubectl create namespace $Namespace
    if ($LASTEXITCODE -ne 0) { throw "kubectl: namespace $Namespace" }
}
kubectl -n $Namespace create secret tls $SecretName --cert=$cert --key=$key --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw "kubectl: secret $SecretName" }

Write-Host "Secret $Namespace/$SecretName holds a certificate for $HostName. Next: ./scripts/deploy.ps1"
