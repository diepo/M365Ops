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

    # BUG reale a DUE livelli, trovato dal vivo il 21/08/2026 durante uno stress test mirato
    # ("mai dare per scontato che non esistano bug non ancora scoperti") - stesso meccanismo di
    # fondo gia' visto piu' volte in questo progetto (sezione 20.5 della guida), ma qui in una
    # combinazione non ancora vista altrove:
    # (1) "$enriched = foreach (...) {...}" collassa a uno SCALARE (PSCustomObject singolo, non
    #     array) quando c'e' ESATTAMENTE UN dispositivo non conforme - richiede @(...) attorno
    #     al foreach per restare sempre un array.
    # (2) ANCHE con $enriched gia' un vero array, "$enriched | ConvertTo-Json" (in PIPELINE)
    #     collassa comunque a un oggetto nudo "{...}" con un array a un solo elemento - verificato
    #     empiricamente: un vero Object[] con Count=1 pipeIato in ConvertTo-Json produce
    #     ancora {"a":1}, non [{"a":1}]. Serve "-InputObject", mai la pipe, stesso principio gia'
    #     documentato in Add-M365OpsKnowledgeDocument.ps1 e in piu' endpoint di Server.ps1.
    # Entrambi i livelli erano necessari: il primo da solo non bastava. Riprodotto empiricamente
    # con un dispositivo sintetico prima di correggere - il prompt AI chiede esplicitamente di
    # "raggruppare QUESTI dispositivi" (plurale), un oggetto nudo con un tenant quasi sano (un
    # solo dispositivo non conforme) avrebbe silenziosamente rotto quell'istruzione.
    $enriched = @(foreach ($d in $devices) {
        [pscustomobject]@{
            device = $d
            reasons = Get-M365OpsDeviceComplianceReasons -Id $d.id
        }
    })

    $context = ConvertTo-Json -InputObject $enriched -Depth 8

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
