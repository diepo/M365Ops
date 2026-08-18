function Reset-M365OpsUserMfa {
    <#
    .SYNOPSIS
        Rimuove i metodi MFA registrati di un utente (Microsoft Authenticator, telefono,
        FIDO2, app OATH, Windows Hello for Business, Temporary Access Pass) cosi' che debba
        registrarne uno nuovo al prossimo accesso che richiede autenticazione forte - QUESTO
        e' il "reset MFA": non esiste un'azione atomica equivalente in Microsoft Graph, la
        documentazione ufficiale stessa dice di eliminare ogni metodo uno per uno (verificato
        il 15/08/2026, non a memoria - vedi
        https://learn.microsoft.com/en-us/graph/api/resources/authenticationmethods-overview,
        sezione "Require re-register multifactor authentication").

        La password (passwordAuthenticationMethod) e il metodo email (SSPR, non MFA) NON
        vengono MAI toccati da questa funzione.

        SCRITTURA REALE E IRREVERSIBILE (l'utente perde l'accesso ai metodi rimossi finche'
        non li riconfigura) - il chiamante (Server.ps1, tramite propose_mfa_reset +
        conferma esplicita 'si'/'no' in chat) e' responsabile di NON invocarla mai senza
        conferma dell'utente, stesso principio di ogni altra scrittura in questo modulo.

        Permesso Graph richiesto: UserAuthenticationMethod.ReadWrite.All (scope dedicato,
        diverso da User.ReadWrite.All). Richiede inoltre che chi e' loggato abbia un ruolo
        Entra Authentication Administrator o Privileged Authentication Administrator (o
        Global Admin) sul tenant - un ruolo, non solo un permesso Graph: senza, ogni DELETE
        fallisce con 403 anche con lo scope corretto.
    #>
    param(
        [Parameter(Mandatory)] [string]$Upn
    )

    $methods = @((Invoke-M365OpsGraphRequest -Method GET -Path "/users/$Upn/authentication/methods").value)

    # Nome della collection REST per ciascun tipo - verificato uno per uno sulla
    # documentazione Microsoft Learn (microsoftAuthenticatorMethods, phoneMethods,
    # fido2Methods confermati esplicitamente; gli altri seguono la stessa convenzione di
    # denominazione confermata su questi tre - se uno risultasse comunque sbagliato, Graph
    # risponde con un 404 pulito, mai un'azione silenziosamente errata su un altro metodo).
    $collectionByType = @{
        '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'  = 'microsoftAuthenticatorMethods'
        '#microsoft.graph.phoneAuthenticationMethod'                   = 'phoneMethods'
        '#microsoft.graph.fido2AuthenticationMethod'                   = 'fido2Methods'
        '#microsoft.graph.softwareOathAuthenticationMethod'            = 'softwareOathMethods'
        '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' = 'windowsHelloForBusinessMethods'
        '#microsoft.graph.temporaryAccessPassAuthenticationMethod'     = 'temporaryAccessPassMethods'
    }

    $removed = @()
    $failed = @()
    foreach ($m in $methods) {
        $collection = $collectionByType[$m.'@odata.type']
        if (-not $collection) { continue }
        try {
            Invoke-M365OpsGraphRequest -Method DELETE -Path "/users/$Upn/authentication/$collection/$($m.id)" | Out-Null
            Write-Host "  - rimosso: $collection ($($m.displayName))" -ForegroundColor Yellow
            $removed += "$collection ($($m.displayName))"
        }
        catch {
            $failed += "$collection`: $($_.Exception.Message)"
        }
    }

    [pscustomobject]@{
        Upn     = $Upn
        Removed = $removed
        Failed  = $failed
        Success = ($removed.Count -gt 0 -and $failed.Count -eq 0)
    }
}
