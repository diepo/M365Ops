function Get-M365OpsLogHistory {
    <#
    .SYNOPSIS
        Cerca nella cronologia dei log applicativi (Logs\m365ops-YYYYMMDD.log, un file al
        giorno, scritti da Write-M365OpsLog) su piu' giorni, con filtri opzionali.

        Nota sulla ritenzione: NESSUN codice del modulo cancella mai un file di log - restano
        sul disco indefinitamente finche' non li rimuove manualmente l'utente. "Almeno 6 mesi
        di storico" e' quindi gia' garantito oggi per costruzione (il limite pratico e' solo
        quanti giorni indietro si sceglie di cercare con -Days, non quanti esistono davvero
        su disco). Restituisce le righe piu' recenti per prime.
    .PARAMETER Days
        Quanti giorni indietro cercare (oggi incluso). 30 di default, usa un numero piu' alto
        (es. 183 per ~6 mesi, 365 per un anno) per andare oltre.
    #>
    param(
        [int]$Days = 30,
        [string]$Search,
        [ValidateSet('Info', 'Warn', 'Error')] [string]$Level,
        [string]$Tenant,
        [int]$MaxResults = 500
    )

    $logDir = Join-Path $script:M365OpsModuleRoot 'Logs'
    if (-not (Test-Path $logDir)) { return @() }

    $cutoff = (Get-Date).Date.AddDays(-[Math]::Max($Days, 0))
    $files = Get-ChildItem -Path $logDir -Filter 'm365ops-*.log' -File | Where-Object {
        if ($_.BaseName -match 'm365ops-(\d{8})$') {
            try { [datetime]::ParseExact($Matches[1], 'yyyyMMdd', $null) -ge $cutoff } catch { $true }
        }
        else { $true }
    } | Sort-Object Name -Descending

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $files) {
        $lines = Get-Content -Path $f.FullName -ErrorAction SilentlyContinue
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $parts = $lines[$i] -split "`t", 4
            if ($parts.Count -lt 4) { continue }
            $entryLevel = $parts[1] -replace '[\[\]]', ''
            if ($Level -and $entryLevel -ne $Level) { continue }
            if ($Tenant -and $parts[2] -notlike "*$Tenant*") { continue }
            if ($Search -and $parts[3] -notlike "*$Search*" -and $parts[2] -notlike "*$Search*") { continue }
            $results.Add([pscustomobject]@{
                Timestamp = $parts[0]
                Level     = $entryLevel
                Tenant    = $parts[2]
                Message   = $parts[3]
            })
            if ($results.Count -ge $MaxResults) { break }
        }
        if ($results.Count -ge $MaxResults) { break }
    }
    $results
}
