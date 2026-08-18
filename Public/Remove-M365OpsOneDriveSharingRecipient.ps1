function Remove-M365OpsOneDriveSharingRecipient {
    <#
    .SYNOPSIS
        Terzo passo del workaround "accesso negato nonostante lo sharing OneDrive": rimuove il
        permesso di -RecipientUpn su un elemento specifico (-ItemName) del OneDrive di -OwnerUpn,
        oppure - se -ItemName e' omesso - cerca tra gli elementi nella radice del OneDrive
        qualunque permesso concesso a -RecipientUpn e li rimuove tutti, riportando cosa e' stato
        toccato. Richiede che Grant-M365OpsOneDriveDelegateAccess sia gia' stato eseguito (serve
        accesso admin al OneDrive per leggere/modificare permessi altrui).
    .PARAMETER ItemName
        Nome esatto del file/cartella (com'e' visibile in OneDrive) su cui rimuovere il permesso
        di RecipientUpn - se lo conosci, usalo: e' piu' rapido e mirato della scansione completa.
    .NOTES
        La scansione senza -ItemName copre solo gli elementi nella RADICE del OneDrive, non
        scende nelle sottocartelle (potenzialmente centinaia/migliaia di elementi) - se il file
        condiviso e' annidato, serve indicare -ItemName o il nome della cartella contenitore.

        BUG REALE trovato dal vivo il 18/08/2026, durante il primo test end-to-end di questo
        stesso workaround: un permesso con ruolo "owner" su un elemento NON rappresenta mai una
        condivisione fatta dal proprietario a un collega (quella da' sempre ruolo "read"/"write")
        - rappresenta invece il proprietario stesso o CHIUNQUE sia stato reso amministratore
        della raccolta siti (esattamente quello che fa Grant-M365OpsOneDriveDelegateAccess al
        passo 1). Se -RecipientUpn coincide per errore con l'admin appena concesso (o e' lui
        stesso un site collection admin per altri motivi), la scansione trovava il suo permesso
        "owner" derivato e tentava di cancellarlo item per item - la cancellazione NON aveva
        pero' alcun effetto reale (il permesso e' calcolato dallo stato di site collection admin,
        non un record indipendente cancellabile: riappare identico subito dopo), quindi nessun
        danno e' stato fatto, ma il comando riportava falsamente "N permessi rimossi" senza aver
        rimosso nulla di vero. Ora i permessi con ruolo "owner" vengono sempre esclusi dalla
        scansione/rimozione - non sono mai il bersaglio corretto per questo comando.
    #>
    param(
        [Parameter(Mandatory)] [string]$OwnerUpn,
        [Parameter(Mandatory)] [string]$RecipientUpn,
        [string]$ItemName
    )

    $items = if ($ItemName) {
        @(Invoke-M365OpsGraphRequest -Method GET -Path "/users/$OwnerUpn/drive/root/children?`$select=id,name" |
            Select-Object -ExpandProperty value | Where-Object { $_.name -eq $ItemName })
    } else {
        @(Invoke-M365OpsGraphRequest -Method GET -Path "/users/$OwnerUpn/drive/root/children?`$select=id,name" |
            Select-Object -ExpandProperty value)
    }
    if ($items.Count -eq 0) {
        throw "Nessun elemento trovato nella radice del OneDrive di '$OwnerUpn'$(if ($ItemName) { " con nome '$ItemName'" })."
    }

    $removed = @()
    foreach ($item in $items) {
        $perms = $null
        try { $perms = Invoke-M365OpsGraphRequest -Method GET -Path "/users/$OwnerUpn/drive/items/$($item.id)/permissions" } catch { continue }
        foreach ($p in @($perms.value)) {
            if ($p.roles -contains 'owner') { continue }
            $grantedEmail = $p.grantedToV2.user.email
            if (-not $grantedEmail) { $grantedEmail = $p.grantedTo.user.email }
            if ($grantedEmail -and $grantedEmail -eq $RecipientUpn) {
                Invoke-M365OpsGraphRequest -Method DELETE -Path "/users/$OwnerUpn/drive/items/$($item.id)/permissions/$($p.id)" | Out-Null
                $removed += [pscustomobject]@{ ItemName = $item.name; PermissionId = $p.id; Roles = ($p.roles -join ',') }
            }
        }
    }

    if ($removed.Count -eq 0) {
        Write-Host "Nessun permesso di $RecipientUpn trovato $(if ($ItemName) { "su '$ItemName'" } else { 'negli elementi radice' }) del OneDrive di $OwnerUpn." -ForegroundColor Yellow
    } else {
        Write-Host "Rimossi $($removed.Count) permesso/i di $RecipientUpn dal OneDrive di $OwnerUpn." -ForegroundColor Green
    }
    [pscustomobject]@{ OwnerUpn = $OwnerUpn; RecipientUpn = $RecipientUpn; RemovedCount = $removed.Count; Removed = $removed }
}
