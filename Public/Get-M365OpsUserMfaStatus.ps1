function Get-M365OpsUserMfaStatus {
    <#
    .SYNOPSIS
        Elenca i metodi di autenticazione registrati da un utente (Microsoft Authenticator,
        telefono, FIDO2, Windows Hello for Business, app OATH, Temporary Access Pass, ecc.) -
        usati per capire se e come ha configurato l'MFA.

        Non esiste nell'API v1.0 di Microsoft Graph un singolo flag "MFA abilitata/richiesta"
        per utente: la pagina "Authentication states" (vedere/impostare lo stato MFA per-utente)
        e' esplicitamente NON ANCORA SUPPORTATA in v1.0 - e' governata da Conditional Access o
        dalle vecchie impostazioni per-utente (Microsoft Entra admin center, non Graph v1.0).
        Il modo corretto per valutare la situazione, verificato sulla documentazione reale
        (non a memoria - vedi link sotto), e' guardare QUALI metodi risultano registrati: se
        c'e' solo la password, l'utente non ha configurato nessun metodo di verifica aggiuntivo.

        Verificato il 15/08/2026 su:
        https://learn.microsoft.com/en-us/graph/api/authentication-list-methods
        https://learn.microsoft.com/en-us/graph/api/resources/authenticationmethods-overview

        Permesso Graph richiesto: UserAuthenticationMethod.Read.All (delegato, per leggere i
        metodi di un ALTRO utente) - diverso da User.Read.All, e' uno scope dedicato. Per un
        tenant Delegated, chi ha fatto login deve inoltre avere un ruolo Entra Global Reader,
        Authentication Administrator o Privileged Authentication Administrator: senza, Graph
        risponde 403 anche con lo scope corretto (e' un requisito di ruolo, non solo di scope).
    #>
    param(
        [Parameter(Mandatory)] [string]$Upn
    )

    $methods = @((Invoke-M365OpsGraphRequest -Method GET -Path "/users/$Upn/authentication/methods").value)

    $typeLabels = @{
        '#microsoft.graph.passwordAuthenticationMethod'                 = 'Password'
        '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'   = 'Microsoft Authenticator'
        '#microsoft.graph.phoneAuthenticationMethod'                    = 'Telefono (SMS/chiamata)'
        '#microsoft.graph.fido2AuthenticationMethod'                    = 'Chiave di sicurezza FIDO2'
        '#microsoft.graph.softwareOathAuthenticationMethod'             = 'App OATH (TOTP)'
        '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod'  = 'Windows Hello for Business'
        '#microsoft.graph.temporaryAccessPassAuthenticationMethod'      = 'Temporary Access Pass'
        '#microsoft.graph.emailAuthenticationMethod'                    = 'Email (solo reset password, NON e'' un metodo MFA)'
        '#microsoft.graph.platformCredentialAuthenticationMethod'       = 'Platform credential'
        '#microsoft.graph.qrCodePinAuthenticationMethod'                = 'QR code + PIN (frontline worker)'
    }
    # Escluse dal conteggio "MFA configurata": la password e' il fattore primario (non un
    # secondo fattore) e il metodo email serve solo per Self-Service Password Reset, non per MFA.
    $notMfaTypes = @('#microsoft.graph.passwordAuthenticationMethod', '#microsoft.graph.emailAuthenticationMethod')

    $registered = $methods | ForEach-Object {
        [pscustomobject]@{
            Type        = if ($typeLabels.ContainsKey($_.'@odata.type')) { $typeLabels[$_.'@odata.type'] } else { $_.'@odata.type' }
            RawType     = $_.'@odata.type'
            Id          = $_.id
            DisplayName = $_.displayName
        }
    }
    $mfaMethods = @($registered | Where-Object { $_.RawType -notin $notMfaTypes })

    [pscustomobject]@{
        Upn           = $Upn
        MfaConfigured = ($mfaMethods.Count -gt 0)
        MfaMethods    = $mfaMethods
        AllMethods    = $registered
    }
}
