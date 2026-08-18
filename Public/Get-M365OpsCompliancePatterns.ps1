function Get-M365OpsCompliancePatterns {
    <#
    .SYNOPSIS
        Recupera i dispositivi non conformi + le cause per ciascuno, e chiede al motore AI
        di raggruppare, correlare e spiegare — nessuna regola scritta a mano nel codice.

    .EXAMPLE
        Get-M365OpsCompliancePatterns -Provider Claude
    #>
    param(
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude'
    )

    $devices = Get-M365OpsManagedDevices -NonCompliantOnly
    if (-not $devices) {
        return "Nessun dispositivo non conforme trovato."
    }

    $enriched = foreach ($d in $devices) {
        [pscustomobject]@{
            device = $d
            reasons = Get-M365OpsDeviceComplianceReasons -Id $d.id
        }
    }

    $context = $enriched | ConvertTo-Json -Depth 8

    $prompt = @"
Analizza questi dispositivi Intune non conformi (dati grezzi da Microsoft Graph).
Raggruppali per causa comune, cerca correlazioni su modello hardware o altri attributi
condivisi, e per ogni gruppo proponi una remediation. Se un campo si contraddice con
un altro (es. complianceState dice 'compliant' ma il dispositivo e' nella lista dei
non conformi), segnalalo esplicitamente invece di ignorarlo o inventare una spiegazione.
Se non trovi correlazioni forti, dillo chiaramente invece di forzarne una.
"@

    Invoke-M365OpsAgent -Prompt $prompt -Context $context -Provider $Provider -MaxTokens 3000
}
