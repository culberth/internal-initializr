<#
.SYNOPSIS
    Proves the site's menu and the Nexus agree: generates projects from the running site and builds
    them against Nexus alone.

.DESCRIPTION
    Reads the menu from the live site (the Initializr metadata API), so there is no second list to
    keep in step. For the default Boot version (or -BootVersion) it:
      1. Downloads a project with every dependency on the menu (or one per dependency with
         -PerDependency).
      2. Checks the generated Maven wrapper downloads Maven from -NexusUrl.
      3. Builds it with ./mvnw.cmd, a settings.xml that mirrors everything to -NexusUrl, an empty
         local repository and an empty wrapper home - so Maven itself, every plugin and every
         dependency must come from Nexus.

    Limits, on purpose: tests are skipped (the generated contextLoads test would need the
    databases and brokers on the menu running), so Surefire's test-time providers are not proven.
    This Nexus is online and proxies Maven Central, so a pass proves "resolves through Nexus", not
    "Nexus already holds it" - on a truly offline Nexus the same run proves both.

.EXAMPLE
    ./scripts/verify-generated-projects.ps1
    ./scripts/verify-generated-projects.ps1 -BootVersion 4.0.8 -PerDependency
#>
param(
    [string]$SiteUrl = "https://initializr.claude.local",
    [string]$NexusUrl = "http://localhost:8081/repository/maven-public",
    [string]$BootVersion = "",
    [string]$JavaVersion = "21",
    [switch]$PerDependency
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $root "build/verify"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$meta = Invoke-RestMethod -Uri "$SiteUrl/" -Headers @{ Accept = "application/vnd.initializr.v2.2+json" }
if (-not $BootVersion) { $BootVersion = $meta.bootVersion.default }
$ids = @($meta.dependencies.values | ForEach-Object { $_.values } | ForEach-Object { $_.id })
Write-Host "Site offers Boot $(@($meta.bootVersion.values.id) -join ', '); verifying $BootVersion with $($ids.Count) dependencies" -ForegroundColor Cyan

$settings = Join-Path $work "nexus-only-settings.xml"
@"
<settings>
  <mirrors>
    <mirror>
      <id>nexus</id>
      <mirrorOf>*</mirrorOf>
      <url>$NexusUrl</url>
    </mirror>
  </mirrors>
</settings>
"@ | Set-Content -Path $settings -Encoding UTF8

# A list of dependency lists: one per dependency, or a single list with all of them.
$cases = [System.Collections.Generic.List[object]]::new()
if ($PerDependency) { foreach ($id in $ids) { $cases.Add(@($id)) } } else { $cases.Add($ids) }
$results = @()
$i = 0
foreach ($deps in $cases) {
    $i++
    $name = if ($PerDependency) { $deps[0] } else { "all" }
    $dir = Join-Path $work "p$i-$name"
    $zip = "$dir.zip"
    $query = "type=maven-project&language=java&bootVersion=$BootVersion&javaVersion=$JavaVersion" +
             "&groupId=com.example&artifactId=verify&name=verify&packageName=com.example.verify&baseDir=verify" +
             "&dependencies=$($deps -join ',')"
    Invoke-WebRequest -Uri "$SiteUrl/starter.zip?$query" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $dir
    $project = Join-Path $dir "verify"

    $wrapper = Get-Content (Join-Path $project ".mvn/wrapper/maven-wrapper.properties") |
        Where-Object { $_ -like "distributionUrl=*" }
    $wrapperOk = $wrapper -like "distributionUrl=$NexusUrl/*"

    # Fresh wrapper home and local repo per run: nothing may come from this machine's caches.
    $env:MAVEN_USER_HOME = Join-Path $work "mvnw-home"
    Push-Location $project
    try {
        & .\mvnw.cmd -B -q -s $settings "-Dmaven.repo.local=$(Join-Path $work 'm2')" package -DskipTests
        $buildOk = ($LASTEXITCODE -eq 0)
    }
    finally {
        Pop-Location
        Remove-Item Env:\MAVEN_USER_HOME
    }
    $results += [pscustomobject]@{ Case = $name; WrapperFromNexus = $wrapperOk; BuildsFromNexus = $buildOk }
}

$results | Format-Table -AutoSize
if ($results | Where-Object { -not $_.WrapperFromNexus -or -not $_.BuildsFromNexus }) {
    Write-Host "FAILED - see the table. Missing artifacts are named in the Maven output above." -ForegroundColor Red
    exit 1
}
Write-Host "All generated projects resolve Maven, plugins and dependencies through $NexusUrl" -ForegroundColor Green
