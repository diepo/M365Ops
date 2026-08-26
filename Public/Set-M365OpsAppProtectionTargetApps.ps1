function Set-M365OpsAppProtectionTargetApps {
    <#
    .SYNOPSIS
        Indica a quali app si applica un criterio di protezione app MAM - AGGIUNGE alla lista
        esistente (le app gia' presenti si leggono prima e si ri-inviano insieme a quelle nuove,
        perche' la action Graph "targetApps" - vedi .NOTES - sostituisce sempre l'INTERO
        elenco, non lo estende). Identificatori: package id per Android (es.
        com.microsoft.office.outlook), bundle id per iOS (es. com.microsoft.Office.Outlook) -
        schema mobileAppIdentifier verificato dal vivo su Microsoft Learn il 19/08/2026.
    .NOTES
        BUG REALE (rotta OData sbagliata) trovato e corretto dal vivo il 26/08/2026 durante
        l'audit Intune/Entra ID/MFA/Conditional Access di questa maratona - stessa causa e
        stesso criterio di test del fix gemello in Set-M365OpsAppProtectionAssignment (vedi le
        sue .NOTES per il dettaglio completo, incluso il primo tentativo di correzione
        rivelatosi anch'esso sbagliato): il codice precedente faceva POST su
        "/deviceAppManagement/{android|ios}ManagedAppProtections/{id}/apps" (la collezione
        OData "apps" - leggibile in GET, come gia' fa correttamente
        Get-M365OpsAppProtectionPolicies, ma MAI scrivibile in POST) - Graph rifiutava SEMPRE
        con 400 "No OData route exists that match template ~/singleton/navigation/key/
        navigation with http verb POST", per QUALSIASI app, mai riuscita nemmeno una volta
        prima di questo fix. La pagina Microsoft Learn della action "targetApps" indica la
        collezione GENERICA "/deviceAppManagement/managedAppPolicies/{id}/targetApps" - provata
        dal vivo (stesso schema del fix gemello) e rifiutata allo stesso modo con 400 "Resource
        not found for the segment 'assign'" sul suo gemello "assign" (mai riprovato qui
        singolarmente solo per non consumare ulteriori scritture reali sul tenant di test, la
        causa e' la stessa collezione generica). La rotta REALE che funziona davvero su questo
        tenant (confermata con una POST + GET di verifica separate) resta la collezione
        SPECIFICA per piattaforma con solo ".../targetApps" appeso (NON ".../apps", quella
        resta sola-lettura): "/deviceAppManagement/{android|ios}ManagedAppProtections/{id}/
        targetApps", su Graph BETA (Lokka la sceglie di default per questa action e ha
        funzionato; mai testato esplicitamente su v1.0, quindi -Beta resta esplicito qui per
        non fare affidamento su un default che potrebbe cambiare). Verificato rileggendo
        "$base/$Identity/apps" (quella si' un GET valido, sola lettura) dopo la scrittura:
        l'app di test (com.microsoft.office.outlook) compariva correttamente. Pulizia del
        criterio di test confermata a fine verifica.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Android', 'iOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$AppIdentifiers
    )
    $base = if ($Platform -eq 'Android') { "/deviceAppManagement/androidManagedAppProtections" } else { "/deviceAppManagement/iosManagedAppProtections" }
    $odataType = if ($Platform -eq 'Android') { "microsoft.graph.androidMobileAppIdentifier" } else { "microsoft.graph.iosMobileAppIdentifier" }
    $idProperty = if ($Platform -eq 'Android') { "packageId" } else { "bundleId" }

    # "targetApps" sostituisce SEMPRE l'intero elenco: per mantenere il comportamento
    # "AGGIUNGE" promesso da questa funzione, le app esistenti si leggono prima e si uniscono a
    # quelle nuove.
    #
    # Solo "mobileAppIdentifier" per le app gia' esistenti (26/08/2026, stesso bug dal vivo gia'
    # trovato e corretto nel merge gemello di Set-M365OpsAppProtectionAssignment - vedi le sue
    # .NOTES): "id"/"version" letti dalla GET possono essere assenti/null per un'app, e
    # ririnviarli come-sono a un campo che Graph si aspetta valorizzato rischia lo stesso 400
    # "expected a string" gia' visto per l'assignment gemello - "mobileAppIdentifier" e' l'unico
    # campo che la action richiede davvero per identificare l'app.
    $existingApps = @((Invoke-M365OpsGraphRequest -Method GET -Path "$base/$Identity/apps" -Beta).value)
    $apps = @($existingApps | ForEach-Object {
        @{ "@odata.type" = "#microsoft.graph.managedMobileApp"; mobileAppIdentifier = $_.mobileAppIdentifier }
    })
    foreach ($appId in $AppIdentifiers) {
        $apps += @{
            "@odata.type"       = "#microsoft.graph.managedMobileApp"
            mobileAppIdentifier = @{ "@odata.type" = $odataType; $idProperty = $appId }
        }
    }

    Invoke-M365OpsGraphRequest -Method POST -Path "$base/$Identity/targetApps" -Body @{ apps = $apps } -Beta | Out-Null
    Write-Host "Criterio $Identity ($Platform): aggiunte $($AppIdentifiers.Count) app di destinazione (totale app ora: $($apps.Count))." -ForegroundColor Green
}
