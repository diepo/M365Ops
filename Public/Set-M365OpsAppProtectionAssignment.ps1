function Set-M365OpsAppProtectionAssignment {
    <#
    .SYNOPSIS
        Assegna un criterio di protezione app (MAM) a uno o piu' gruppi - AGGIUNGE alle
        assegnazioni esistenti (non le sostituisce): le assegnazioni gia' presenti si leggono
        prima e si ri-inviano insieme a quelle nuove, perche' la action Graph "assign" (vedi
        .NOTES) sostituisce sempre l'INTERO elenco, non lo estende - stesso principio gia'
        documentato in Set-M365OpsDeviceScriptAssignment per la sua action "assign".
        Per rimuovere un'assegnazione usa Remove-M365OpsAppProtectionAssignment.
    .NOTES
        BUG REALE (rotta OData sbagliata) trovato e corretto dal vivo il 26/08/2026 durante
        l'audit Intune/Entra ID/MFA/Conditional Access di questa maratona - creato un criterio
        di test (ZZTEST-marathon-AppProtection, Android) e provata un'assegnazione reale: il
        codice precedente faceva POST su
        "/deviceAppManagement/{android|ios}ManagedAppProtections/{id}/assignments" (la
        collezione OData "assignments", che si presumeva scrivibile con un POST diretto per la
        mancanza apparente di una action "assign" dedicata) - Graph rifiutava SEMPRE con 400
        "No OData route exists that match template ~/singleton/navigation/key/navigation with
        http verb POST", per QUALSIASI gruppo, mai riuscita nemmeno una volta prima di questo
        fix.
        PRIMO TENTATIVO di correzione (rivelatosi anch'esso sbagliato, lasciato qui come nota
        perche' la documentazione Microsoft Learn NON basta da sola, va sempre riverificata dal
        vivo): la pagina "targetedManagedAppPolicyAssignment" di Microsoft Learn suggerisce la
        action "assign" sulla collezione GENERICA "/deviceAppManagement/managedAppPolicies/{id}/
        assign" - provato dal vivo con propose_graph_write sullo stesso criterio di test,
        risultato IDENTICO fallimento con un errore diverso ma altrettanto secco: 400
        "Resource not found for the segment 'assign'". La rotta REALE che funziona davvero su
        questo tenant (confermata con una POST/GET di verifica separate, poi ripetuta con
        successo attraverso questa stessa funzione dopo la correzione) resta la collezione
        SPECIFICA per piattaforma con solo ".../assign" appeso (NON ".../assignments", quella
        resta sola-lettura): "/deviceAppManagement/{android|ios}ManagedAppProtections/{id}/
        assign", su Graph BETA (Lokka la sceglie di default per questa action e ha funzionato;
        mai testato esplicitamente su v1.0, quindi -Beta resta esplicito qui per non fare
        affidamento su un default che potrebbe cambiare). Verificato rileggendo
        "$base/$Identity/assignments" (quella si' un GET valido, sola lettura) dopo la
        scrittura: il gruppo di test compariva correttamente. Pulizia del criterio di test
        confermata a fine verifica.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Android', 'iOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds,
        [switch]$Exclude
    )
    $base = if ($Platform -eq 'Android') { "/deviceAppManagement/androidManagedAppProtections" } else { "/deviceAppManagement/iosManagedAppProtections" }
    $targetType = if ($Exclude) { "#microsoft.graph.exclusionGroupAssignmentTarget" } else { "#microsoft.graph.groupAssignmentTarget" }

    # "assign" sostituisce SEMPRE l'intero elenco: per mantenere il comportamento "AGGIUNGE"
    # promesso da questa funzione (e dal catalogo comandi esposto all'AI), le assegnazioni
    # esistenti si leggono prima e si uniscono a quelle nuove.
    #
    # BUG REALE trovato dal vivo il 26/08/2026 (stesso test di cui sopra, secondo giro dopo la
    # correzione della rotta): la GET su ".../assignments" NON include un "@odata.type" a
    # livello di singolo elemento (solo il "target" annidato ce l'ha) - ririnviare
    # $_.'@odata.type' (null) come proprieta' di primo livello faceva rifiutare l'INTERA POST
    # con 400 "expected a string for ODataType value", per QUALSIASI assegnazione gia'
    # esistente sul criterio. Basta reinviare "target" (unico campo che la action richiede
    # davvero, "id" e "@odata.type" dell'assignment sono ridondanti/derivati da Graph stesso -
    # verificato dal vivo: la nuova assegnazione tornava con un id "<groupId>_incl" generato
    # automaticamente, mai fornito in input).
    $existing = @((Invoke-M365OpsGraphRequest -Method GET -Path "$base/$Identity/assignments" -Beta).value)
    $assignments = @($existing | ForEach-Object {
        @{ target = $_.target }
    })
    foreach ($groupId in $TargetGroupIds) {
        $assignments += @{
            "@odata.type" = "#microsoft.graph.targetedManagedAppPolicyAssignment"
            target        = @{ "@odata.type" = $targetType; groupId = $groupId }
        }
    }

    Invoke-M365OpsGraphRequest -Method POST -Path "$base/$Identity/assign" -Body @{ assignments = $assignments } -Beta | Out-Null
    $mode = if ($Exclude) { "esclusione" } else { "inclusione" }
    Write-Host "Criterio $Identity ($Platform): aggiunti $($TargetGroupIds.Count) gruppo/i in $mode (totale assegnazioni ora: $($assignments.Count))." -ForegroundColor Green
}
