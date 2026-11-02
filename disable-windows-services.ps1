#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables Windows services and features that most desktop users do not need
    (telemetry, error reporting, Superfetch, touch keyboard, fax, Recall), then
    prints a short analysis of what is still running.

.DESCRIPTION
    Before changing anything, the script saves the original state of every item
    it touches to a JSON backup. Run it again with -Undo to restore exactly that
    state. The backup is written only once, so running the script twice never
    overwrites the true original values.

.PARAMETER Undo
    Restores everything from the backup file.

.PARAMETER AnalyzeOnly
    Changes nothing. Only prints the analysis.

.PARAMETER BackupPath
    Where the backup is stored. Default: %ProgramData%\disable-windows-services\backup.json

.EXAMPLE
    .\disable-windows-services.ps1               # disable + analysis
    .\disable-windows-services.ps1 -AnalyzeOnly  # just look
    .\disable-windows-services.ps1 -Undo         # restore original state
#>
[CmdletBinding()]
param(
    [switch] $Undo,
    [switch] $AnalyzeOnly,
    [string] $BackupPath = (Join-Path $env:ProgramData 'disable-windows-services\backup.json')
)

$ErrorActionPreference = 'Continue'

$services = @(
    @{ Name = 'DiagTrack';          Desc = 'Connected User Experiences and Telemetry' }
    @{ Name = 'dmwappushservice';   Desc = 'WAP push message routing (telemetry)' }
    @{ Name = 'WerSvc';             Desc = 'Windows Error Reporting' }
    @{ Name = 'SysMain';            Desc = 'Superfetch (little benefit on fast SSD/NVMe)' }
    @{ Name = 'TabletInputService'; Desc = 'Touch keyboard and handwriting panel' }
    @{ Name = 'Fax';                Desc = 'Fax' }
    @{ Name = 'CDPUserSvc';         Desc = 'Connected Devices Platform (per-user template)' }
)

$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
$policies   = @('DisableAIDataAnalysis', 'DisableClickToDo')
$startNames = @{ 0 = 'Boot'; 1 = 'System'; 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }

function Get-ServiceStart([string] $Name) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path $key)) { return $null }
    return (Get-ItemProperty -Path $key -Name Start -ErrorAction SilentlyContinue).Start
}

function Get-PolicyValue([string] $Name) {
    if (-not (Test-Path $policyPath)) { return $null }
    return (Get-ItemProperty -Path $policyPath -Name $Name -ErrorAction SilentlyContinue).$Name
}

function Test-RecallEnabled {
    $info = dism /online /get-featureinfo /featurename:Recall 2>&1
    return [bool]($info | Select-String -SimpleMatch 'State : Enabled')
}

function Show-Analysis {
    Write-Host ""
    Write-Host "=== ANALYSIS ===" -ForegroundColor Cyan
    Write-Host "--- Target services ---" -ForegroundColor Yellow
    foreach ($svc in $services) {
        $start = Get-ServiceStart $svc.Name
        if ($null -eq $start) { continue }
        $status = 'n/a'
        $svcObj = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($svcObj) { $status = $svcObj.Status }
        Write-Host ("  {0,-20} Startup={1,-10} Status={2}" -f $svc.Name, $startNames[[int]$start], $status)
    }

    Write-Host ""
    Write-Host "--- Top 15 service hosts by memory ---" -ForegroundColor Yellow
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match 'svchost|service' } |
        Sort-Object WS -Descending |
        Select-Object -First 15 ProcessName, @{ N = 'MemMB'; E = { [math]::Round($_.WS / 1MB, 1) } }, Id |
        Format-Table -AutoSize

    Write-Host "--- Other services worth reviewing (not changed by this script) ---" -ForegroundColor Yellow
    $suspects = 'XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc','WSearch','Spooler',
                'RemoteRegistry','WMPNetworkSvc','MapsBroker','RetailDemo','WalletService','PhoneSvc'
    foreach ($name in $suspects) {
        try {
            $s = Get-Service -Name $name -ErrorAction Stop
            if ($s.Status -eq 'Running' -or $s.StartType -eq 'Automatic') {
                Write-Host ("  {0,-20} Status={1,-10} Startup={2}" -f $s.Name, $s.Status, $s.StartType)
            }
        } catch { }
    }
}

# ---------------------------------------------------------------- analyze only
if ($AnalyzeOnly) { Show-Analysis; return }

# ---------------------------------------------------------------- undo
if ($Undo) {
    if (-not (Test-Path $BackupPath)) {
        Write-Host "No backup found at $BackupPath. Nothing to restore." -ForegroundColor Red
        exit 1
    }
    $backup = Get-Content $BackupPath -Raw | ConvertFrom-Json
    Write-Host "=== Restoring from $BackupPath (saved $($backup.Created)) ===" -ForegroundColor Cyan

    foreach ($svc in $backup.Services) {
        if ($null -eq $svc.Start) { continue }
        try {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)" -Name Start -Value ([int]$svc.Start) -Type DWord -ErrorAction Stop
            Write-Host ("  [OK]   {0,-20} Startup={1}" -f $svc.Name, $startNames[[int]$svc.Start]) -ForegroundColor Green
        } catch {
            Write-Host "  [FAIL] $($svc.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    foreach ($p in $backup.Policies) {
        if ($null -eq $p.Value) {
            Remove-ItemProperty -Path $policyPath -Name $p.Name -ErrorAction SilentlyContinue
            Write-Host "  [OK]   policy $($p.Name) removed" -ForegroundColor Green
        } else {
            Set-ItemProperty -Path $policyPath -Name $p.Name -Value ([int]$p.Value) -Type DWord
            Write-Host "  [OK]   policy $($p.Name) = $($p.Value)" -ForegroundColor Green
        }
    }

    if ($backup.RecallWasEnabled -and -not (Test-RecallEnabled)) {
        dism /online /enable-feature /featurename:Recall /norestart | Out-Null
        Write-Host "  [OK]   Recall feature re-enabled via DISM" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Restored. Reboot to apply. The backup was kept at $BackupPath." -ForegroundColor Green
    return
}

# ---------------------------------------------------------------- backup
if (Test-Path $BackupPath) {
    Write-Host "Backup already exists at $BackupPath (kept as the original state)." -ForegroundColor DarkGray
} else {
    $backup = [ordered]@{
        Created          = (Get-Date).ToString('s')
        Services         = @($services | ForEach-Object { [ordered]@{ Name = $_.Name; Start = (Get-ServiceStart $_.Name) } })
        Policies         = @($policies | ForEach-Object { [ordered]@{ Name = $_; Value = (Get-PolicyValue $_) } })
        RecallWasEnabled = (Test-RecallEnabled)
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $BackupPath) | Out-Null
    $backup | ConvertTo-Json -Depth 4 | Set-Content -Path $BackupPath -Encoding UTF8
    Write-Host "Original state saved to $BackupPath (use -Undo to restore)." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- disable
Write-Host ""
Write-Host "=== Disabling services ===" -ForegroundColor Cyan
foreach ($svc in $services) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
    if (-not (Test-Path $key)) {
        Write-Host "  [SKIP] $($svc.Name) (not present on this system)" -ForegroundColor DarkGray
        continue
    }
    try {
        $running = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($running -and $running.Status -eq 'Running') {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        }
        # Registry write works for normal services and for per-user templates like CDPUserSvc.
        Set-ItemProperty -Path $key -Name Start -Value 4 -Type DWord -ErrorAction Stop
        Write-Host ("  [OK]   {0,-20} {1}" -f $svc.Name, $svc.Desc) -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] $($svc.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Windows Recall + Click to Do (policy) ===" -ForegroundColor Cyan
if (-not (Test-Path $policyPath)) { New-Item -Path $policyPath -Force | Out-Null }
foreach ($p in $policies) {
    Set-ItemProperty -Path $policyPath -Name $p -Value 1 -Type DWord
    Write-Host "  [OK]   $p = 1" -ForegroundColor Green
}
if (Test-RecallEnabled) {
    dism /online /disable-feature /featurename:Recall /norestart | Out-Null
    Write-Host "  [OK]   Recall feature disabled via DISM" -ForegroundColor Green
}

Show-Analysis
Write-Host ""
Write-Host "Done. Reboot to make sure everything stops. Undo anytime with -Undo." -ForegroundColor Green
