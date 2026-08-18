function Clear-M365OpsChatHistory {
    <#
    .SYNOPSIS
        Azzera lo storico conversazione locale del tenant indicato ("nuova conversazione").
    #>
    param([Parameter(Mandatory)] [string]$TenantName)

    $safeName = $TenantName -replace '[^\w\-]', '_'
    $path = Join-Path $script:M365OpsModuleRoot "Config\ChatHistory-$safeName.json"
    if (Test-Path $path) { Remove-Item -Path $path -Force }
}
