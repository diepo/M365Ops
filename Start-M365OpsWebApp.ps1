param(
    [string]$TenantProfile = "contoso-test",
    [int]$Port = 8743
)

$serverScript = Join-Path $PSScriptRoot 'Gui\Server.ps1'
$url = "http://localhost:$Port/"

Start-Job -ScriptBlock {
    param($url)
    Start-Sleep -Seconds 2
    $edgePath = (Get-Command msedge.exe -ErrorAction SilentlyContinue).Source
    if (-not $edgePath) {
        $candidatePaths = @(
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
            "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
            "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
        )
        $edgePath = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if ($edgePath) {
        Start-Process $edgePath -ArgumentList "--app=$url"
    } else {
        Start-Process $url
    }
} -ArgumentList $url | Out-Null

& $serverScript -TenantProfile $TenantProfile -Port $Port
