function New-M365OpsDistributionGroup {
    <#
    .SYNOPSIS
        Crea una distribution list, opzionalmente con membri iniziali (indirizzi email).
        -ExtraParams passa altri parametri nativi di New-DistributionGroup (es.
        ManagedBy, RequireSenderAuthenticationEnabled, ModeratedBy) - se non sei sicuro
        del nome esatto, consulta prima lookup_ms_docs "New-DistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$PrimarySmtpAddress,
        [string[]]$Members,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress; Type = 'Distribution'; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $dl = New-DistributionGroup @params

    # Bug reale trovato dal vivo il 23/08/2026 (bug-hunt di 16 ore): un membro non valido
    # (typo nell'indirizzo, utente non ancora sincronizzato, ecc.) faceva fallire
    # Add-DistributionGroupMember con -ErrorAction Stop SENZA che questa funzione catturasse
    # l'eccezione - il gruppo era GIA' stato creato con successo da New-DistributionGroup
    # sopra, ma l'eccezione si propagava fino al chiamante (Execute-PendingAction in
    # Gui\Server.ps1), che riportava "la scrittura NON e' andata a buon fine" - falso: il
    # gruppo esisteva davvero sul tenant, solo con alcuni membri iniziali mancanti. Un secondo
    # tentativo di creazione poi falliva con "esiste gia'", confondendo ulteriormente l'utente
    # sullo stato reale. Ora ogni membro viene aggiunto individualmente con il proprio
    # try/catch: il gruppo conta sempre come creato con successo (e' un fatto gia' avvenuto),
    # ed eventuali membri non aggiunti vengono elencati esplicitamente nel risultato invece di
    # far sparire l'intera operazione dietro un'eccezione fuorviante.
    $failedMembers = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $Members) {
        try {
            Add-DistributionGroupMember -Identity $dl.Identity -Member $m -Confirm:$false -ErrorAction Stop
        } catch {
            $failedMembers.Add("$m ($($_.Exception.Message))")
        }
    }
    if ($failedMembers.Count -gt 0) {
        Write-Host "Distribution list creata: $($dl.DisplayName) ($($dl.PrimarySmtpAddress)) - ATTENZIONE, alcuni membri NON sono stati aggiunti: $($failedMembers -join '; ')" -ForegroundColor Yellow
    } else {
        Write-Host "Distribution list creata: $($dl.DisplayName) ($($dl.PrimarySmtpAddress))" -ForegroundColor Green
    }
    $result = $dl | Select-Object DisplayName, PrimarySmtpAddress, GroupType
    if ($failedMembers.Count -gt 0) { $result | Add-Member -NotePropertyName MembriNonAggiunti -NotePropertyValue @($failedMembers) }
    $result
}
