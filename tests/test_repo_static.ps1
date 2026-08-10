$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$composePath = Join-Path $repoRoot "docker-compose.yml"
$updateScript = Join-Path $repoRoot "scripts/update.sh"
$envExample = Join-Path $repoRoot ".env.example"
$safetyDoc = Join-Path $repoRoot "docs/SAFETY.md"
$firewallDoc = Join-Path $repoRoot "docs/firewall.md"
$firewallScript = Join-Path $repoRoot "scripts/apply-firewall-rules.sh"
$backupScript = Join-Path $repoRoot "scripts/backup-config.sh"
$backupService = Join-Path $repoRoot "scripts/backup-config.service"
$backupTimer = Join-Path $repoRoot "scripts/backup-config.timer"
$diskHealthDoc = Join-Path $repoRoot "docs/disk-health.md"
$diskHealthScript = Join-Path $repoRoot "scripts/check-disk-health.sh"
$diskHealthService = Join-Path $repoRoot "scripts/check-disk-health.service"
$diskHealthTimer = Join-Path $repoRoot "scripts/check-disk-health.timer"
$diskLongTestScript = Join-Path $repoRoot "scripts/start-disk-long-test.sh"
$diskLongTestService = Join-Path $repoRoot "scripts/start-disk-long-test.service"
$diskLongTestTimer = Join-Path $repoRoot "scripts/start-disk-long-test.timer"
$restoreScript = Join-Path $repoRoot "scripts/restore-config-test.sh"
$hardlinkScript = Join-Path $repoRoot "scripts/test-hardlinks.sh"
$homepageInstallScript = Join-Path $repoRoot "scripts/install-homepage-config.sh"
$homepageTemplateDir = Join-Path $repoRoot "config-templates/homepage"
$jellyseerrBulkScript = Join-Path $repoRoot "scripts/request-jellyseerr-list.py"
$jellyseerrListGenerator = Join-Path $repoRoot "scripts/generate-jellyseerr-curated-lists.py"
$jellyseerrBulkDoc = Join-Path $repoRoot "docs/jellyseerr/bulk-requests.md"
$afiListCsv = Join-Path $repoRoot "docs/lists/afi-100-years-100-movies.csv"
$nicolasCageListCsv = Join-Path $repoRoot "docs/lists/nicolas-cage-filmography.csv"
$johnWayneListCsv = Join-Path $repoRoot "docs/lists/john-wayne-filmography.csv"
$johnWayneUnavailableCsv = Join-Path $repoRoot "docs/lists/john-wayne-unavailable-in-tmdb.csv"
$bestPictureNomineesCsv = Join-Path $repoRoot "docs/lists/best-picture-nominees.csv"
$marvelMcuProjectsCsv = Join-Path $repoRoot "docs/lists/marvel-mcu-projects.csv"
$marvelMcuUnavailableCsv = Join-Path $repoRoot "docs/lists/marvel-mcu-unavailable-in-tmdb.csv"

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
    "7900 XTX",
    "lazylibrarian",
    "calibre-web-automated",
    "audiobookshelf",
    "suwayomi",
    "kavita",
    '"books"',
    '"manga"',
    "5299",
    "8083",
    "13378",
    "4567",
    "5000"
)) {
    Assert-NotContains -Text $composeText -Pattern [regex]::Escape($bad) -Message "docker-compose.yml still contains old marker: $bad"
    Assert-NotContains -Text $scriptText -Pattern [regex]::Escape($bad) -Message "scripts/update.sh still contains old marker: $bad"
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
    $pattern = "(?ms)^  ${cleanupService}:.*?profiles:\s+\[.*`"cleanup`".*\]"
    Assert-Contains -Text $composeText -Pattern $pattern -Message "$cleanupService must be behind the cleanup profile."
    $badPattern = "(?ms)^  ${cleanupService}:.*?profiles:\s+\[.*first-deploy.*\]"
    Assert-NotContains -Text $composeText -Pattern $badPattern -Message "$cleanupService must not be in first-deploy."
}

foreach ($pair in @(
    @{ Service = "diun"; Profile = "updates" },
    @{ Service = "jellystat"; Profile = "stats" },
    @{ Service = "jellystat-db"; Profile = "stats" },
    @{ Service = "recyclarr"; Profile = "quality" },
    @{ Service = "unpackerr"; Profile = "extract" },
    @{ Service = "autobrr"; Profile = "autobrr" },
    @{ Service = "cross-seed"; Profile = "cross-seed" },
    @{ Service = "qbitmanage"; Profile = "qbitmanage" },
    @{ Service = "cleanuparr"; Profile = "cleanuparr" }
    @{ Service = "pihole"; Profile = "dns" }
)) {
    $pattern = "(?ms)^  $($pair.Service):.*?profiles:\s+\[.*`"$($pair.Profile)`".*\]"
    Assert-Contains -Text $composeText -Pattern $pattern -Message "$($pair.Service) must have explicit profile $($pair.Profile)."
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
    "TAILSCALE_IP",
    "TAILSCALE_SUBNET",
    "FIREWALL_PORTS",
    "FIREWALL_LAN_DNS_PORTS",
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
    "PIHOLE_WEBPASSWORD",
    "NTFY_TOPIC",
    "SMART_DEVICES",
    "SMARTCTL_OPTIONS",
    "SMART_TEMP_WARN_C",
    "SMART_NTFY_URL",
    "SMART_NTFY_TOPIC",
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
foreach ($p in @(
    $safetyDoc,
    $firewallDoc,
    $firewallScript,
    $backupScript,
    $backupService,
    $backupTimer,
    $diskHealthDoc,
    $diskHealthScript,
    $diskHealthService,
    $diskHealthTimer,
    $diskLongTestScript,
    $diskLongTestService,
    $diskLongTestTimer,
    $restoreScript,
    $hardlinkScript,
    $homepageInstallScript,
    $jellyseerrBulkScript,
    $jellyseerrListGenerator,
    $jellyseerrBulkDoc,
    $afiListCsv
)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Missing required safety artifact: $p"
    }
}

$backupServiceText = Get-Content -Raw -Path $backupService
$backupTimerText = Get-Content -Raw -Path $backupTimer
$firewallScriptText = Get-Content -Raw -Path $firewallScript
$firewallDocText = Get-Content -Raw -Path $firewallDoc

Assert-Contains `
    -Text $firewallScriptText `
    -Pattern 'DRY_RUN="\$\{DRY_RUN:-1\}"' `
    -Message "Firewall script must default to dry-run."

Assert-Contains `
    -Text $firewallScriptText `
    -Pattern 'APPLY="\$\{APPLY:-0\}"' `
    -Message "Firewall script must require APPLY=1 before changing UFW."

Assert-Contains `
    -Text $firewallScriptText `
    -Pattern '0\.0\.0\.0/0' `
    -Message "Firewall script must explicitly guard against 0.0.0.0/0."

Assert-Contains `
    -Text $firewallScriptText `
    -Pattern 'ufw default deny incoming' `
    -Message "Firewall script must set default incoming deny."

Assert-Contains `
    -Text $firewallScriptText `
    -Pattern 'ufw allow from "\$\{LAN_SUBNET\}" to any port "\$\{port\}" proto tcp' `
    -Message "Firewall script must allow configured ports from LAN_SUBNET."

Assert-Contains `
    -Text $firewallScriptText `
    -Pattern 'ufw allow from "\$\{TAILSCALE_SUBNET\}" to any port "\$\{port\}" proto tcp' `
    -Message "Firewall script must allow configured ports from TAILSCALE_SUBNET."

foreach ($port in @("22", "80", "3000", "3001", "5055", "6767", "7878", "8081", "8096", "8989", "9696", "2586", "11011")) {
    Assert-Contains `
        -Text $firewallDocText `
        -Pattern "\| $port \|" `
        -Message "Firewall docs must include validated port $port."
}

Assert-Contains `
    -Text $firewallDocText `
    -Pattern 'Default: deny \(incoming\), allow \(outgoing\), deny \(routed\)' `
    -Message "Firewall docs must capture the verified default UFW policy."

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

$diskHealthText = Get-Content -Raw -Path $diskHealthScript
$diskLongTestText = Get-Content -Raw -Path $diskLongTestScript
$diskHealthServiceText = Get-Content -Raw -Path $diskHealthService
$diskHealthTimerText = Get-Content -Raw -Path $diskHealthTimer
$diskLongTestServiceText = Get-Content -Raw -Path $diskLongTestService
$diskLongTestTimerText = Get-Content -Raw -Path $diskLongTestTimer
$diskHealthDocText = Get-Content -Raw -Path $diskHealthDoc

Assert-Contains `
    -Text $diskHealthText `
    -Pattern 'smartctl \$\{SMARTCTL_OPTIONS\} -H -A -l error -l selftest' `
    -Message "check-disk-health.sh must use read-only smartctl health/log checks."

Assert-Contains `
    -Text $diskHealthText `
    -Pattern 'SMART_NTFY_URL' `
    -Message "check-disk-health.sh must support ntfy alerting."

Assert-Contains `
    -Text $diskLongTestText `
    -Pattern 'smartctl \$\{SMARTCTL_OPTIONS\} -t long' `
    -Message "start-disk-long-test.sh must start SMART long tests."

Assert-Contains `
    -Text $diskHealthServiceText `
    -Pattern 'User=root' `
    -Message "SMART health service should run as root for raw disk access."

Assert-Contains `
    -Text $diskHealthServiceText `
    -Pattern 'EnvironmentFile=-/opt/mediastack/\.env' `
    -Message "SMART health service must read .env for SMART_DEVICES and alert settings."

Assert-Contains `
    -Text $diskHealthTimerText `
    -Pattern 'OnCalendar=\*-\*-\* 09:00:00' `
    -Message "SMART health timer must run daily."

Assert-Contains `
    -Text $diskLongTestServiceText `
    -Pattern 'User=root' `
    -Message "SMART long-test service should run as root for raw disk access."

Assert-Contains `
    -Text $diskLongTestTimerText `
    -Pattern 'OnCalendar=Sun \*-\*-1\.\.7 11:30:00' `
    -Message "SMART long-test timer must run monthly on the first Sunday."

Assert-Contains `
    -Text $diskHealthDocText `
    -Pattern '/dev/disk/by-id' `
    -Message "disk-health docs must require stable /dev/disk/by-id paths."

Assert-Contains `
    -Text $diskHealthDocText `
    -Pattern 'TerraMaster D9-320' `
    -Message "disk-health docs must mention TerraMaster D9-320 SMART passthrough."

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
    -Text $homepageServices `
    -Pattern 'href:\s+"http://\{\{HOMEPAGE_VAR_REMOTE_IP\}\}:11011"' `
    -Message "Homepage services must link Cleanuparr through the remote/Tailscale IP."

Assert-Contains `
    -Text $homepageServices `
    -Pattern 'href:\s+"http://\{\{HOMEPAGE_VAR_REMOTE_IP\}\}:3010"' `
    -Message "Homepage services must link Jellystat through the remote/Tailscale IP."

Assert-Contains `
    -Text $homepageServices `
    -Pattern 'href:\s+"http://\{\{HOMEPAGE_VAR_REMOTE_IP\}\}:8053/admin/"' `
    -Message "Homepage services must link Pi-hole through the remote/Tailscale IP."

Assert-Contains `
    -Text $composeText `
    -Pattern '"\$\{LAN_IP:-192\.168\.1\.10\}:53:53/udp"' `
    -Message "Pi-hole DNS must bind UDP 53 specifically to LAN_IP."

Assert-Contains `
    -Text $composeText `
    -Pattern 'FTLCONF_dns_listeningMode=ALL' `
    -Message "Pi-hole must use ALL listening mode on Docker bridge networking."

$firewallScriptText = Get-Content -Raw -Path (Join-Path $repoRoot "scripts/apply-firewall-rules.sh")
Assert-Contains `
    -Text $firewallScriptText `
    -Pattern 'proto udp' `
    -Message "Firewall helper must allow Pi-hole UDP DNS from the LAN."

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "scripts/start-pihole.sh"))) {
    throw "Missing guarded Pi-hole startup script."
}

Assert-Contains `
    -Text $composeText `
    -Pattern 'HOMEPAGE_VAR_REMOTE_IP=\$\{TAILSCALE_IP:-\$\{LAN_IP:-192\.168\.1\.10\}\}' `
    -Message "Homepage compose env must expose a remote/Tailscale IP for clickable links."

Assert-Contains `
    -Text $composeText `
    -Pattern 'HOMEPAGE_VAR_BAZARR_KEY=\$\{BAZARR_APIKEY\}' `
    -Message "Homepage compose env must expose BAZARR_APIKEY for the Bazarr widget."

Assert-Contains `
    -Text $composeText `
    -Pattern 'POSTGRES_DB=jellystat' `
    -Message "Jellystat Postgres must create the database name that the Jellystat app expects."

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

$jellyseerrBulkText = Get-Content -Raw -Path $jellyseerrBulkScript
Assert-Contains `
    -Text $jellyseerrBulkText `
    -Pattern 'parser\.add_argument\("--apply", action="store_true"' `
    -Message "Jellyseerr bulk request script must require --apply before creating requests."

Assert-Contains `
    -Text $jellyseerrBulkText `
    -Pattern "Mode: \{'APPLY' if args\.apply else 'DRY-RUN'\}" `
    -Message "Jellyseerr bulk request script must make dry-run/apply mode visible."

Assert-Contains `
    -Text $jellyseerrBulkText `
    -Pattern 'media_type.*movie' `
    -Message "Jellyseerr bulk request script must default CSV rows to movie media_type."

Assert-Contains `
    -Text $jellyseerrBulkText `
    -Pattern 'body\["seasons"\] = seasons' `
    -Message "Jellyseerr bulk request script must include seasons for TV requests."

Assert-Contains `
    -Text $jellyseerrBulkText `
    -Pattern 'request-existing' `
    -Message "Jellyseerr bulk request script must expose an explicit override for already-tracked media."

Assert-Contains `
    -Text $jellyseerrBulkText `
    -Pattern 'already tracked in Jellyseerr/Seerr' `
    -Message "Jellyseerr bulk request script must skip already available/requested media by default."

Assert-Contains `
    -Text $jellyseerrBulkText `
    -Pattern '/api/v1/\{row\.media_type\}/\{media_id\}' `
    -Message "Jellyseerr bulk request script must status-check TMDB-ID rows through media detail endpoints."

$jellyseerrListGeneratorText = Get-Content -Raw -Path $jellyseerrListGenerator
Assert-Contains `
    -Text $jellyseerrListGeneratorText `
    -Pattern 'https://query\.wikidata\.org/sparql' `
    -Message "Curated list generator must document its Wikidata SPARQL source."

Assert-Contains `
    -Text $jellyseerrListGeneratorText `
    -Pattern 'alfred-hitchcock-filmography\.csv' `
    -Message "Curated list generator must write the Alfred Hitchcock request list."

Assert-Contains `
    -Text $jellyseerrListGeneratorText `
    -Pattern 'best-actor-nominated-films\.csv' `
    -Message "Curated list generator must write the Best Actor nomination request list."

Assert-Contains `
    -Text $jellyseerrListGeneratorText `
    -Pattern 'DIRECTOR_STARTERS' `
    -Message "Curated list generator must expose a starter director batch."

Assert-Contains `
    -Text $jellyseerrListGeneratorText `
    -Pattern 'stanley-kubrick' `
    -Message "Curated list generator must be able to write director filmography lists."

Assert-NotContains `
    -Text $jellyseerrListGeneratorText `
    -Pattern '/api/v1/request' `
    -Message "Curated list generator must not create Jellyseerr requests directly."

$jellyseerrBulkDocText = Get-Content -Raw -Path $jellyseerrBulkDoc
Assert-Contains `
    -Text $jellyseerrBulkDocText `
    -Pattern 'generate-jellyseerr-curated-lists\.py' `
    -Message "Bulk request docs must explain how to generate curated lists."

Assert-Contains `
    -Text $jellyseerrBulkDocText `
    -Pattern 'best-actor-nominated-films\.csv' `
    -Message "Bulk request docs must include Best Actor nomination request commands."

$afiRows = Import-Csv -Path $afiListCsv
if ($afiRows.Count -ne 100) {
    throw "AFI 100 list must contain exactly 100 movie rows; found $($afiRows.Count)."
}

$nicolasCageRows = Import-Csv -Path $nicolasCageListCsv
if ($nicolasCageRows.Count -ne 120) {
    throw "Nicolas Cage list must contain exactly 120 appearance rows; found $($nicolasCageRows.Count)."
}

$missingCageTmdbIds = $nicolasCageRows | Where-Object { -not $_.tmdb_id }
if ($missingCageTmdbIds.Count -ne 0) {
    throw "Every Nicolas Cage row must have a TMDB ID."
}

$duplicateCageTmdbIds = $nicolasCageRows | Group-Object tmdb_id | Where-Object { $_.Count -gt 1 }
if ($duplicateCageTmdbIds.Count -ne 0) {
    throw "Nicolas Cage list contains duplicate TMDB IDs."
}

$johnWayneRows = Import-Csv -Path $johnWayneListCsv
if ($johnWayneRows.Count -ne 171) {
    throw "John Wayne request list must contain exactly 171 TMDB-resolvable films; found $($johnWayneRows.Count)."
}

$invalidJohnWayneIds = $johnWayneRows | Where-Object { -not $_.tmdb_id -or $_.tmdb_id -notmatch '^\d+$' }
if ($invalidJohnWayneIds.Count -ne 0) {
    throw "Every requestable John Wayne row must have a numeric TMDB ID."
}

$duplicateJohnWayneIds = $johnWayneRows | Group-Object tmdb_id | Where-Object { $_.Count -gt 1 }
if ($duplicateJohnWayneIds.Count -ne 0) {
    throw "John Wayne request list contains duplicate TMDB IDs."
}

$johnWayneUnavailableRows = Import-Csv -Path $johnWayneUnavailableCsv
if ($johnWayneUnavailableRows.Count -ne 2) {
    throw "John Wayne unavailable list must preserve exactly two non-TMDB film appearances."
}

$bestPictureRows = Import-Csv -Path $bestPictureNomineesCsv
if ($bestPictureRows.Count -ne 621) {
    throw "Best Picture nominee list must contain exactly 621 movie rows; found $($bestPictureRows.Count)."
}

$invalidBestPictureIds = $bestPictureRows | Where-Object { -not $_.tmdb_id -or $_.tmdb_id -notmatch '^\d+$' }
if ($invalidBestPictureIds.Count -ne 0) {
    throw "Every Best Picture nominee row must have a numeric TMDB ID."
}

$duplicateBestPictureRanks = $bestPictureRows | Group-Object rank | Where-Object { $_.Count -gt 1 }
if ($duplicateBestPictureRanks.Count -ne 0) {
    throw "Best Picture nominee list contains duplicate rank values."
}

$marvelRows = Import-Csv -Path $marvelMcuProjectsCsv
if ($marvelRows.Count -ne 79) {
    throw "Marvel MCU project list must contain exactly 79 requestable rows; found $($marvelRows.Count)."
}

$invalidMarvelIds = $marvelRows | Where-Object { -not $_.tmdb_id -or $_.tmdb_id -notmatch '^\d+$' }
if ($invalidMarvelIds.Count -ne 0) {
    throw "Every requestable Marvel row must have a numeric TMDB ID."
}

$invalidMarvelMediaTypes = $marvelRows | Where-Object { $_.media_type -notin @("movie", "tv") }
if ($invalidMarvelMediaTypes.Count -ne 0) {
    throw "Every requestable Marvel row must use media_type movie or tv."
}

$marvelTvRows = $marvelRows | Where-Object { $_.media_type -eq "tv" }
if ($marvelTvRows.Count -lt 1) {
    throw "Marvel MCU project list must include TV rows."
}

$requiredMarvelTitles = @(
    "Agents of S.H.I.E.L.D.",
    "Daredevil",
    "Jessica Jones",
    "Luke Cage",
    "Iron Fist",
    "The Defenders",
    "The Punisher"
)
foreach ($title in $requiredMarvelTitles) {
    if (-not ($marvelRows | Where-Object { $_.title -eq $title })) {
        throw "Marvel MCU project list is missing required title: $title"
    }
}

$marvelUnavailableRows = Import-Csv -Path $marvelMcuUnavailableCsv
if ($marvelUnavailableRows.Count -ne 3) {
    throw "Marvel MCU unavailable list must preserve exactly three not-yet-requestable announced projects."
}

$genrePillarLists = @(
    @{ Path = Join-Path $repoRoot "docs/lists/noir-essentials.csv"; MinRows = 20 },
    @{ Path = Join-Path $repoRoot "docs/lists/western-essentials.csv"; MinRows = 20 },
    @{ Path = Join-Path $repoRoot "docs/lists/sci-fi-essentials.csv"; MinRows = 20 },
    @{ Path = Join-Path $repoRoot "docs/lists/horror-classics.csv"; MinRows = 20 },
    @{ Path = Join-Path $repoRoot "docs/lists/seventies-new-hollywood.csv"; MinRows = 20 },
    @{ Path = Join-Path $repoRoot "docs/lists/nineties-crime-thriller.csv"; MinRows = 20 }
)

foreach ($list in $genrePillarLists) {
    if (-not (Test-Path $list.Path)) {
        throw "Missing genre pillar list: $($list.Path)"
    }

    $rows = Import-Csv -Path $list.Path
    if ($rows.Count -lt $list.MinRows) {
        throw "Genre pillar list $($list.Path) must contain at least $($list.MinRows) rows; found $($rows.Count)."
    }

    $missingRequiredFields = $rows | Where-Object {
        -not $_.rank -or -not $_.title -or -not $_.year -or -not $_.notes
    }
    if ($missingRequiredFields.Count -ne 0) {
        throw "Genre pillar list $($list.Path) has rows missing rank, title, year, or notes."
    }

    $duplicateRows = $rows | Group-Object title, year | Where-Object { $_.Count -gt 1 }
    if ($duplicateRows.Count -ne 0) {
        throw "Genre pillar list $($list.Path) contains duplicate title/year rows."
    }
}

$genrePillarScript = Join-Path $repoRoot "scripts/request-genre-pillars.sh"
$genrePillarScriptText = Get-Content -Raw -Path $genrePillarScript
Assert-Contains `
    -Text $genrePillarScriptText `
    -Pattern 'APPLY="\$\{APPLY:-0\}"' `
    -Message "Genre pillar wrapper must default to dry-run mode."

Assert-Contains `
    -Text $genrePillarScriptText `
    -Pattern '--apply' `
    -Message "Genre pillar wrapper must support explicit apply mode."

$requiredGenreListNames = @(
    "noir-essentials.csv",
    "western-essentials.csv",
    "sci-fi-essentials.csv",
    "horror-classics.csv",
    "seventies-new-hollywood.csv",
    "nineties-crime-thriller.csv"
)
foreach ($name in $requiredGenreListNames) {
    $escapedName = [regex]::Escape($name)
    Assert-Contains `
        -Text $genrePillarScriptText `
        -Pattern $escapedName `
        -Message "Genre pillar wrapper is missing $name."

    Assert-Contains `
        -Text $jellyseerrBulkDocText `
        -Pattern $escapedName `
        -Message "Bulk request docs are missing $name."
}

$directorDeepDiveScript = Join-Path $repoRoot "scripts/generate-director-deep-dive.sh"
$directorDeepDiveScriptText = Get-Content -Raw -Path $directorDeepDiveScript
Assert-Contains `
    -Text $directorDeepDiveScriptText `
    -Pattern 'START_AT="\$\{START_AT:-\}"' `
    -Message "Director deep-dive generator must support START_AT resume."

Assert-Contains `
    -Text $directorDeepDiveScriptText `
    -Pattern 'SLEEP_SECONDS="\$\{SLEEP_SECONDS:-75\}"' `
    -Message "Director deep-dive generator must pause between Wikidata queries."

foreach ($slug in @("scorsese", "coppola", "ridley-scott")) {
    Assert-Contains `
        -Text $directorDeepDiveScriptText `
        -Pattern $slug `
        -Message "Director deep-dive generator is missing $slug."
}

$movieExpansionScript = Join-Path $repoRoot "scripts/request-movie-expansion-wave.sh"
$movieExpansionScriptText = Get-Content -Raw -Path $movieExpansionScript
Assert-Contains `
    -Text $movieExpansionScriptText `
    -Pattern 'APPLY="\$\{APPLY:-0\}"' `
    -Message "Movie expansion wave wrapper must default to dry-run mode."

Assert-Contains `
    -Text $movieExpansionScriptText `
    -Pattern 'WAVE="\$\{WAVE:-all\}"' `
    -Message "Movie expansion wave wrapper must support wave selection."

Assert-Contains `
    -Text $movieExpansionScriptText `
    -Pattern 'martin-scorsese-filmography\.csv' `
    -Message "Movie expansion wave wrapper must use the generated Scorsese filename."

Assert-Contains `
    -Text $movieExpansionScriptText `
    -Pattern 'best-actor-nominated-films\.csv' `
    -Message "Movie expansion wave wrapper must include Best Actor nominations."

Assert-Contains `
    -Text $movieExpansionScriptText `
    -Pattern 'nicolas-cage-filmography\.csv' `
    -Message "Movie expansion wave wrapper must include existing actor lists."

$jellyseerrBulkDocText = Get-Content -Raw -Path $jellyseerrBulkDoc
Assert-Contains `
    -Text $jellyseerrBulkDocText `
    -Pattern 'request-movie-expansion-wave\.sh' `
    -Message "Bulk request docs must document the movie expansion wave wrapper."

Assert-Contains `
    -Text $jellyseerrBulkDocText `
    -Pattern 'generate-director-deep-dive\.sh' `
    -Message "Bulk request docs must document the director deep-dive generator."

Write-Host "Static repository safety checks passed."
