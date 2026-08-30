function Protect-M365OpsSecretText {
    <#
    .SYNOPSIS
        Redige eventuali segreti in chiaro presenti in un testo prima che venga persistito su
        disco (log, storico chat) - es. il corpo JSON di una scrittura Graph proposta con
        "password":"..." (creazione utente con passwordProfile, reset password, ecc.).

        Estratta come funzione condivisa il 31/08/2026 (bug reale trovato dalla maratona di
        stress-test): questa stessa redazione esisteva GIA' solo dentro
        Add-M365OpsChatHistoryTurn.ps1 (applicata allo storico chat), ma NON era mai stata
        applicata a Write-M365OpsWriteLog.ps1 - che riceve lo stesso identico contenuto (il
        corpo JSON completo di una scrittura Graph, via Format-M365OpsCommandLine/
        $lokkaCmdText in Gui\Server.ps1) e lo scrive PERMANENTEMENTE su Logs\writes-*.log
        (mai cancellato automaticamente). Un utente che crea un account con
        propose_graph_write specificando passwordProfile.password vedeva quella password
        finire in chiaro nel log delle scritture, un buco gia' chiuso per lo storico chat ma
        mai propagato qui. Estratta in un solo posto condiviso cosi' le due destinazioni non
        possano piu' divergere in futuro.
    .PARAMETER Text
        Testo da redigere - puo' essere $null/vuoto, restituito invariato in quel caso.
    #>
    param([AllowNull()] [AllowEmptyString()] [string]$Text)

    if (-not $Text) { return $Text }
    return ($Text -replace '("password"\s*:\s*")[^"]*(")', '$1[REDACTED]$2')
}
