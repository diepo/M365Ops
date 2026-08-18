function Set-M365OpsLastReportPath {
    <#
    .SYNOPSIS
        Imposta $script:LastReportPath nello scope del MODULO - funzione ponte per Server.ps1
        (che vive in un altro scope) quando genera un report dal catalogo comandi deterministico,
        senza passare dall'AI (es. Export-M365OpsDeviceReportChat).
    .NOTES
        Bug reale osservato dal vivo il 18/08/2026: un report generato dal catalogo imposta SOLO
        $script:LastReportPath dentro Server.ps1 - se l'utente chiede poi, in un turno separato,
        di inviarlo per email, propose_send_report_email (dentro Invoke-M365OpsAgentTools.ps1, nel
        MODULO) legge la SUA COPIA di $script:LastReportPath, sempre vuota in quel caso, e risponde
        "il file del report precedente non risulta piu' disponibile" anche se il file esiste
        davvero su disco - stessa classe di bug di scope gia' vista piu' volte in questo progetto,
        stavolta nella direzione opposta (Server.ps1 scrive, il modulo deve leggere).
    #>
    param([Parameter(Mandatory)] [string]$Path)
    $script:LastReportPath = $Path
}
