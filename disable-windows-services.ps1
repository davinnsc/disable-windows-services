# Disable useless Windows services + run analysis
# Run as ADMIN

$ErrorActionPreference = "Continue"

Write-Host "=== Disabling services ===" -ForegroundColor Cyan

$services = @(
    @{Name="DiagTrack";           Desc="MS Telemetry"},
    @{Name="dmwappushservice";    Desc="WAP push telemetry"},
    @{Name="WerSvc";              Desc="Error Reporting"},
    @{Name="SysMain";             Desc="Superfetch (useless on NVMe)"},
    @{Name="TabletInputService";  Desc="Touch keyboard"},
    @{Name="Fax";                 Desc="Fax"}
)

foreach ($svc in $services) {
    $name = $svc.Name
    $desc = $svc.Desc
    try {
        $s = Get-Service -Name $name -ErrorAction Stop
        if ($s.Status -eq 'Running') {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
        Write-Host "  [OK]   $name ($desc)" -ForegroundColor Green
    } catch {
        Write-Host "  [SKIP] $name - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== CDPUserSvc (per-user template, via registry) ===" -ForegroundColor Cyan
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\CDPUserSvc" -Name "Start" -Value 4 -Type DWord
    Write-Host "  [OK]   CDPUserSvc disabled in registry (effect after logoff)" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] CDPUserSvc: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Windows Recall + Click to Do (via policy) ===" -ForegroundColor Cyan
try {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name "DisableAIDataAnalysis" -Value 1 -Type DWord
    Set-ItemProperty -Path $regPath -Name "DisableClickToDo"      -Value 1 -Type DWord
    Write-Host "  [OK]   Recall + Click to Do disabled via policy" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] WindowsAI policy: $($_.Exception.Message)" -ForegroundColor Red
}

# Also try DISM (if the feature exists)
$recallFeature = dism /online /get-featureinfo /featurename:Recall 2>&1 | Select-String "State : Enabled"
if ($recallFeature) {
    dism /online /disable-feature /featurename:Recall /norestart | Out-Null
    Write-Host "  [OK]   Recall feature disabled via DISM" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== POST-DISABLE ANALYSIS ===" -ForegroundColor Cyan
Write-Host ""

# Final status of target services
Write-Host "--- Target service status ---" -ForegroundColor Yellow
$allTargets = $services.Name + @("CDPUserSvc")
foreach ($name in $allTargets) {
    $regKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (Test-Path $regKey) {
        $startVal = (Get-ItemProperty -Path $regKey -Name Start -ErrorAction SilentlyContinue).Start
        $startMap = @{0="Boot"; 1="System"; 2="Automatic"; 3="Manual"; 4="Disabled"}
        $startStr = $startMap[[int]$startVal]
        try {
            $svcObj = Get-Service -Name $name -ErrorAction Stop
            $status = $svcObj.Status
        } catch { $status = "n/a" }
        Write-Host ("  {0,-22} Startup={1,-10} Status={2}" -f $name, $startStr, $status)
    }
}

Write-Host ""
Write-Host "--- Top 15 svchost by memory ---" -ForegroundColor Yellow
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match 'svchost|service' } |
    Sort-Object WS -Descending |
    Select-Object -First 15 ProcessName, @{N='MemMB';E={[math]::Round($_.WS/1MB,1)}}, @{N='CPU';E={[math]::Round($_.CPU,1)}}, Id |
    Format-Table -AutoSize

Write-Host ""
Write-Host "--- Other running services worth reviewing ---" -ForegroundColor Yellow
$suspects = @("XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc","WSearch","Spooler","RemoteRegistry","WMPNetworkSvc","MapsBroker","RetailDemo","WalletService","Fax","PhoneSvc")
foreach ($name in $suspects) {
    try {
        $s = Get-Service -Name $name -ErrorAction Stop
        if ($s.Status -eq 'Running' -or $s.StartType -eq 'Automatic') {
            Write-Host ("  {0,-22} Status={1,-10} Startup={2}" -f $s.Name, $s.Status, $s.StartType)
        }
    } catch { }
}

Write-Host ""
Write-Host "Done. Reboot to ensure everything stops." -ForegroundColor Green
