$LocalZip          = "resourcepacks\Ottonien.zip"
$RepoOwner         = "Ottonien"
$RepoName          = "ottonien-reformed"
$GithubApiUrl      = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
$AssetName         = "Ottonien.zip"
$LogFile           = "ord-latest.log"

Start-Transcript -Path $LogFile -IncludeInvocationHeader

if (-not (Test-Path $LocalZip)) {
    Write-Host "Lokale ZIP existiert nicht. Erzeuge leere Datei zum Vergleich."
    New-Item -Path $LocalZip -ItemType File -Force
}


$LocalHash = (Get-FileHash -Path $LocalZip -Algorithm SHA256).Hash
Write-Host "Lokaler SHA256: $LocalHash"

$headers = @{
    "Accept"           = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

try {
    $Release = Invoke-RestMethod -Uri $GithubApiUrl -Method Get -Headers $headers
} catch {
    Write-Error "GitHub-API-Abfrage fehlgeschlagen: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

$Asset = $Release.assets | Where-Object { $_.name -eq $AssetName }
if (-not $Asset) {
    Write-Warning "Kein Asset namens '$AssetName' im Release gefunden."
    Stop-Transcript
    exit 0
}

$RemoteTag          = $Release.tag_name
$RemoteUrl          = $Asset.browser_download_url
$RemoteDigestField  = $Asset.digest

if (-not $RemoteDigestField) {
    Write-Warning "Kein SHA256-Hash im Release-Asset gefunden. Eventuell Hashes nicht aktiviert."
    Write-Host "Nur Versions-Tag-Vergleich: Lokale ZIP wird nicht automatisch ersetzt."
    Stop-Transcript
    exit 0
}

$RemoteHash = $RemoteDigestField.Trim().ToUpper()
if ($RemoteHash -match "^sha256:([a-fA-F0-9]{64})$") {
    $RemoteHash = $Matches[1]
}

if ($RemoteHash -eq $LocalHash) {
    Write-Host "Lokale ZIP ist aktuell (Tag: $RemoteTag, Hash: $RemoteHash)."
    Stop-Transcript
    exit 0
}

Write-Host "Neue Version erkannt (Tag: $RemoteTag)."
Write-Host "Lokal:  $LocalHash"
Write-Host "Remote: $RemoteHash"

$TempZip = [System.IO.Path]::GetTempFileName() + ".zip"

try {
    Write-Host "Lade neue ZIP herunter: $RemoteUrl"
    Invoke-WebRequest -Uri $RemoteUrl -OutFile $TempZip -ErrorAction Stop

    $DownloadedHash = (Get-FileHash -Path $TempZip -Algorithm SHA256).Hash
    if ($DownloadedHash -ne $RemoteHash) {
        Write-Error "Der heruntergeladene Hash ($DownloadedHash) stimmt nicht mit dem Remote-Hash ($RemoteHash) überein."
        Remove-Item -Path $TempZip -Force
        Stop-Transcript
        exit 1
    }

    Move-Item -Path $TempZip -Destination $LocalZip -Force
    Write-Host "Lokale ZIP wurde erfolgreich durch neue Version ersetzt."
} catch {
    Write-Error "Fehler beim Download oder Ersetzen der ZIP: $($_.Exception.Message)"
    if (Test-Path $TempZip) {
        Remove-Item -Path $TempZip -Force
    }
    Stop-Transcript
    exit 1
}
