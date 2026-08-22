function Invoke-M365OpsIsolatedCmdlet {
    <#
    .SYNOPSIS
        Corpo reale di OGNI funzione proxy generata da Connect-M365OpsIsolatedModule - inoltra
        una chiamata cmdlet al processo isolato del modulo/tenant giusti, avviandolo al volo se
        il tenant attivo non ne ha ancora uno (es. appena passato a un tenant mai usato da
        quando l'isolamento e' scattato per questo modulo, in un'altra sessione di tenant).
    #>
    param(
        [Parameter(Mandatory)] [string]$ModuleType,
        [Parameter(Mandatory)] [string]$Cmdlet,
        [hashtable]$Parameters = @{}
    )

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    $process = if ($script:M365OpsIsolatedWorkers -and $script:M365OpsIsolatedWorkers[$tenantName]) { $script:M365OpsIsolatedWorkers[$tenantName][$ModuleType] } else { $null }
    if (-not $process -or $process.HasExited) {
        $connectParams = Get-M365OpsIsolatedConnectParams -ModuleType $ModuleType
        Connect-M365OpsIsolatedModule -ModuleType $ModuleType -ConnectParams $connectParams
        $process = $script:M365OpsIsolatedWorkers[$tenantName][$ModuleType]
    }
    if (-not $process) { throw "Impossibile avviare il processo isolato per $ModuleType." }

    $response = Invoke-M365OpsMcpRequest -Process $process -Method "invoke" -Params @{ cmdlet = $Cmdlet; parameters = $Parameters }

    # $response e' gia' il valore di "result" dopo un giro di ConvertFrom-Json
    # (Invoke-M365OpsMcpRequest) - ma il worker lo popola con una STRINGA JSON (vedi
    # M365OpsIsolatedWorker.ps1, "invoke": ConvertTo-Json sul risultato vero), quindi serve un
    # secondo ConvertFrom-Json per ottenere gli oggetti PowerShell reali, non solo il testo.
    if ($null -eq $response) { return $null }
    try { return ($response | ConvertFrom-Json -ErrorAction Stop) } catch { return $response }
}
