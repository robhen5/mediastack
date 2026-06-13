$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$composePath = Join-Path $repoRoot "docker-compose.yml"
$updateScript = Join-Path $repoRoot "scripts/update.sh"
$envExample = Join-Path $repoRoot ".env.example"
$safetyDoc = Join-Path $repoRoot "docs/SAFETY.md"
$backupScript = Join-Path $repoRoot "scripts/backup-config.sh"
$backupService = Join-Path $repoRoot "scripts/backup-config.service"
$backupTimer = Join-Path $repoRoot "scripts/backup-config.timer"
$restoreScript = Join-Path $repoRoot "scripts/restore-config-test.sh"
$hardlinkScript = Join-Path $repoRoot "scripts/test-hardlinks.sh"
$homepageInstallScript = Join-Path $repoRoot "scripts/install-homepage-config.sh"
$homepageTemplateDir = Join-Path $repoRoot "config-templates/homepage"

$composeText = Get-Content -Raw -Path $composePath
$scriptText = Get-Content -Raw -Path $updateScript
$envText = Get-Content -Raw -Path $envExample

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

Assert-Contains `
    -Text $scriptText `
    -Pattern 'DRY_RUN' `
    -Message "scripts/update.sh must expose a DRY_RUN mode before cleanup commands can run."

Assert-Contains `
    -Text $scriptText `
    -Pattern 'run docker image prune -f' `
    -Message "docker image prune must go through the dry-run aware run wrapper."

Assert-Contains `
    -Text $scriptText `
    -Pattern 'UPDATE_PROFILES="\$\{UPDATE_PROFILES:-first-deploy monitoring dashboard\}"' `
    -Message "scripts/update.sh must select safe default compose profiles."

Assert-Contains `
    -Text $scriptText `
    -Pattern 'compose up -d' `
    -Message "scripts/update.sh should apply updates through the profile-aware compose wrapper."

Assert-Contains `
    -Text $scriptText `
    -Pattern 'MEDIASTACK_DIR="\$\{MEDIASTACK_DIR:-\$\{MEDIASTACK_ROOT:-/opt/mediastack\}\}"' `
    -Message "scripts/update.sh should allow MEDIASTACK_DIR or MEDIASTACK_ROOT override."

Assert-Contains `
    -Text $composeText `
    -Pattern '\$\{CONFIG_ROOT:-/opt/mediastack/config\}' `
    -Message "docker-compose.yml must use CONFIG_ROOT for app config."

Assert-Contains `
    -Text $composeText `
    -Pattern '\$\{DATA_ROOT:-/media/storage/data\}' `
    -Message "docker-compose.yml must use DATA_ROOT for media/downloads."

Assert-Contains `
    -Text $composeText `
    -Pattern '/dev/dri:/dev/dri\s+# Intel Quick Sync' `
    -Message "Jellyfin hardware acceleration note should reference Intel Quick Sync."

foreach ($bad in @(
    "/home/xavierb",
    "America/Denver",
    "CachyOS",
    "AMD VAAPI",
    "7900 XTX"
)) {
    Assert-NotContains -Text $composeText -Pattern [regex]::Escape($bad) -Message "docker-compose.yml still contains old marker: $bad"
}

$firstDeployExpected = @(
    "bazarr",
    "gluetun",
    "jellyfin",
    "jellyseerr",
    "prowlarr",
    "qbittorrent",
    "radarr",
    "sonarr"
) | Sort-Object

$currentService = $null
$firstDeployActual = New-Object System.Collections.Generic.List[string]
foreach ($line in (Get-Content -Path $composePath)) {
    if ($line -match '^  ([A-Za-z0-9_-]+):\s*$') {
        $currentService = $Matches[1]
        continue
    }

    if ($currentService -and $line -match 'profiles:\s+\[.*"first-deploy".*\]') {
        $firstDeployActual.Add($currentService)
    }
}

$firstDeployActualSorted = $firstDeployActual | Sort-Object
if (($firstDeployActualSorted -join ",") -ne ($firstDeployExpected -join ",")) {
    throw "first-deploy profile mismatch. Expected: $($firstDeployExpected -join ', '); got: $($firstDeployActualSorted -join ', ')"
}

foreach ($cleanupService in @("qbitmanage", "cleanuparr")) {
    $pattern = "(?ms)^  ${cleanupService}:.*?profiles:\s+\[`"cleanup`"\]"
    Assert-Contains -Text $composeText -Pattern $pattern -Message "$cleanupService must be behind the cleanup profile."
    $badPattern = "(?ms)^  ${cleanupService}:.*?profiles:\s+\[.*first-deploy.*\]"
    Assert-NotContains -Text $composeText -Pattern $badPattern -Message "$cleanupService must not be in first-deploy."
}

$monitoringExpected = @(
    "ntfy",
    "uptime-kuma"
) | Sort-Object

$currentService = $null
$monitoringActual = New-Object System.Collections.Generic.List[string]
foreach ($line in (Get-Content -Path $composePath)) {
    if ($line -match '^  ([A-Za-z0-9_-]+):\s*$') {
        $currentService = $Matches[1]
        continue
    }

    if ($currentService -and $line -match 'profiles:\s+\[.*"monitoring".*\]') {
        $monitoringActual.Add($currentService)
    }
}

$monitoringActualSorted = $monitoringActual | Sort-Object
if (($monitoringActualSorted -join ",") -ne ($monitoringExpected -join ",")) {
    throw "monitoring profile mismatch. Expected: $($monitoringExpected -join ', '); got: $($monitoringActualSorted -join ', ')"
}

$dashboardExpected = @(
    "homepage"
) | Sort-Object

$currentService = $null
$dashboardActual = New-Object System.Collections.Generic.List[string]
foreach ($line in (Get-Content -Path $composePath)) {
    if ($line -match '^  ([A-Za-z0-9_-]+):\s*$') {
        $currentService = $Matches[1]
        continue
    }

    if ($currentService -and $line -match 'profiles:\s+\[.*"dashboard".*\]') {
        $dashboardActual.Add($currentService)
    }
}

$dashboardActualSorted = $dashboardActual | Sort-Object
if (($dashboardActualSorted -join ",") -ne ($dashboardExpected -join ",")) {
    throw "dashboard profile mismatch. Expected: $($dashboardExpected -join ', '); got: $($dashboardActualSorted -join ', ')"
}

$scriptFiles = Get-ChildItem -Path (Join-Path $repoRoot "scripts") -Filter "*.sh"
foreach ($file in $scriptFiles) {
    $text = Get-Content -Raw -Path $file.FullName
    if ($text -match 'rm\s+-rf') {
        throw "Unexpected recursive delete command found in script: $($file.Name)"
    }
}

foreach ($name in @(
    "TZ",
    "PUID",
    "PGID",
    "RENDER_GID",
    "VIDEO_GID",
    "DOCKER_GID",
    "MEDIASTACK_ROOT",
    "CONFIG_ROOT",
    "BACKUP_ROOT",
    "DATA_ROOT",
    "LAN_IP",
    "LAN_SUBNET",
    "WIREGUARD_PRIVATE_KEY",
    "WIREGUARD_ADDRESSES",
    "QBIT_USER",
    "QBIT_PASS",
    "SONARR_APIKEY",
    "RADARR_APIKEY",
    "PROWLARR_APIKEY",
    "BAZARR_APIKEY",
    "JELLYFIN_APIKEY",
    "JELLYSTAT_DB_PASSWORD",
    "JELLYSTAT_JWT_SECRET",
    "NTFY_TOPIC",
    "QBT_DRY_RUN",
    "UNPACKERR_DELETE_DELAY"
)) {
    Assert-Contains -Text $envText -Pattern "(?m)^$name=" -Message ".env.example missing $name."
}

# Safety-pass invariants: dry-run / non-destructive defaults must survive any
# future compose edit. Each assertion has a one-line reason; if you intend
# to change one of these, update docs/SAFETY.md alongside the test.

Assert-Contains `
    -Text $envText `
    -Pattern '(?m)^QBT_DRY_RUN=true' `
    -Message ".env.example must default QBT_DRY_RUN=true so qbit_manage starts report-only."

Assert-Contains `
    -Text $envText `
    -Pattern '(?m)^UNPACKERR_DELETE_DELAY=9999h' `
    -Message ".env.example must default UNPACKERR_DELETE_DELAY=9999h so unpackerr does not delete extracted files during 30-day safe mode."

Assert-Contains `
    -Text $composeText `
    -Pattern 'QBT_DRY_RUN=\$\{QBT_DRY_RUN:-true\}' `
    -Message "qbit_manage compose env must default QBT_DRY_RUN to true."

Assert-Contains `
    -Text $composeText `
    -Pattern 'UN_SONARR_0_DELETE_ORIG=false' `
    -Message "Unpackerr must default UN_SONARR_0_DELETE_ORIG=false (do not delete .rar originals)."

Assert-Contains `
    -Text $composeText `
    -Pattern 'UN_RADARR_0_DELETE_ORIG=false' `
    -Message "Unpackerr must default UN_RADARR_0_DELETE_ORIG=false (do not delete .rar originals)."

Assert-Contains `
    -Text $composeText `
    -Pattern 'UN_SONARR_0_DELETE_DELAY=\$\{UNPACKERR_DELETE_DELAY:-9999h\}' `
    -Message "Unpackerr must default UN_SONARR_0_DELETE_DELAY to UNPACKERR_DELETE_DELAY (9999h)."

Assert-Contains `
    -Text $composeText `
    -Pattern 'UN_RADARR_0_DELETE_DELAY=\$\{UNPACKERR_DELETE_DELAY:-9999h\}' `
    -Message "Unpackerr must default UN_RADARR_0_DELETE_DELAY to UNPACKERR_DELETE_DELAY (9999h)."

# Required safety scripts and the SAFETY.md doc must exist.
foreach ($p in @($safetyDoc, $backupScript, $backupService, $backupTimer, $restoreScript, $hardlinkScript, $homepageInstallScript)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Missing required safety artifact: $p"
    }
}

$backupServiceText = Get-Content -Raw -Path $backupService
$backupTimerText = Get-Content -Raw -Path $backupTimer

Assert-Contains `
    -Text $backupServiceText `
    -Pattern 'ExecStart=/opt/mediastack/scripts/backup-config\.sh' `
    -Message "backup-config.service must run the repo backup script."

Assert-Contains `
    -Text $backupServiceText `
    -Pattern 'EnvironmentFile=-/opt/mediastack/\.env' `
    -Message "backup-config.service must read /opt/mediastack/.env for BACKUP_ROOT."

Assert-Contains `
    -Text $backupTimerText `
    -Pattern 'OnCalendar=Sun \*-\*-\* 10:15:00' `
    -Message "backup-config.timer must run weekly on Sunday morning."

Assert-Contains `
    -Text $backupTimerText `
    -Pattern 'Persistent=true' `
    -Message "backup-config.timer must catch up missed runs after boot."

foreach ($name in @("settings.yaml", "services.yaml", "widgets.yaml", "bookmarks.yaml", "docker.yaml")) {
    $path = Join-Path $homepageTemplateDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing Homepage template: $path"
    }
}

$homepageServices = Get-Content -Raw -Path (Join-Path $homepageTemplateDir "services.yaml")
Assert-Contains `
    -Text $homepageServices `
    -Pattern 'url:\s+http://gluetun:8080' `
    -Message "Homepage qBittorrent widget must use gluetun:8080 because qBittorrent shares Gluetun's network namespace."

Assert-Contains `
    -Text $composeText `
    -Pattern 'HOMEPAGE_VAR_BAZARR_KEY=\$\{BAZARR_APIKEY\}' `
    -Message "Homepage compose env must expose BAZARR_APIKEY for the Bazarr widget."

# The safety scripts themselves must not contain `rm -rf` (already checked by
# the existing rm-rf rule for scripts/*.sh, but the doc-side rule is here).
$safetyText = Get-Content -Raw -Path $safetyDoc
Assert-Contains `
    -Text $safetyText `
    -Pattern 'first 30 days' `
    -Message "docs/SAFETY.md must document the first-30-days safe operating mode."

Assert-Contains `
    -Text $safetyText `
    -Pattern 'Restore rehearsal checklist' `
    -Message "docs/SAFETY.md must include a restore rehearsal checklist."

Assert-Contains `
    -Text $safetyText `
    -Pattern 'Remaining risks' `
    -Message "docs/SAFETY.md must summarize remaining risks after the safety pass."

Write-Host "Static repository safety checks passed."
