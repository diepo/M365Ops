function Connect-M365OpsIntune {
    <#
    .SYNOPSIS
        Connette a Microsoft Graph per Intune (modulo di terze parti IntuneWin32App,
        usato da New-M365OpsWin32App) sul tenant attivo. Su tenant AppOnly e' silenziosa
        (client credentials). Su tenant Delegated richiede un login interattivo che BLOCCA
        il processo finche' non completato - a differenza di ExchangeOnlineManagement, il
        modulo IntuneWin32App non offre un parametro per iniettare un token gia' ottenuto,
        quindi qui NON e' possibile un flusso asincrono a due passi come per Graph/Exchange
        (verificato: Connect-MSIntuneGraph v1.5.0 ha solo ClientSecret/ClientCert/
        Interactive/DeviceCode, nessun AccessToken).

        USA -Interactive, NON -DeviceCode: verificato leggendo il sorgente del modulo
        (Private\New-DeviceCodeAccessToken.ps1, v1.5.0) che il flusso -DeviceCode ha un bug
        reale che lo rende SEMPRE fallito su PowerShell 7 - il gestore d'errore del ciclo di
        polling chiama $ErrorResponse.GetResponseStream(), un metodo che esiste solo su
        System.Net.WebResponse (.NET Framework), non su System.Net.Http.HttpResponseMessage
        (le eccezioni di Invoke-RestMethod in .NET Core/PS7) - crolla sul primissimo
        "authorization_pending" (la risposta NORMALE finche' l'utente non ha ancora
        completato il login), quindi il ciclo non arriva mai a completarsi, a prescindere
        da quanto in fretta si inserisca il codice. -Interactive (Private\
        New-DelegatedAccessToken.ps1) e' un flusso PKCE con redirect su localhost scritto
        da zero, non condivide questo bug, ed e' anzi meglio per la domanda "sono sicuro
        che sia l'utenza giusta?": apre il browser con prompt=select_account, quindi
        l'utente sceglie esplicitamente l'account invece di subire un eventuale riuso
        silenzioso di una sessione cache.

        ClientID su tenant Delegated: dalla v1.0.5 IntuneWin32App richiede sempre -ClientID
        esplicito, non ha piu' un client id di default proprio (verificato sul sorgente
        GitHub del modulo). Ma -ClientID accetta QUALUNQUE app Azure AD valida, non
        necessariamente una registrata da noi - qui si riusa lo stesso client pubblico
        Microsoft di prima parte ("Microsoft Graph Command Line Tools",
        $script:M365OpsDeviceCodeClientId) gia' usato con successo per il login Graph di
        questo stesso tenant, per NON richiedere una nuova App Registration solo per
        Intune. Se il tenant non ha mai dato consenso admin ai permessi Intune per questa
        app, potrebbe comparire una schermata di consenso nel browser durante questo stesso
        login (l'utente puo' acconsentire li' se ha i permessi) - se invece fallisce con un
        errore di consenso (AADSTS65001), serve un consenso admin una tantum (Entra ID ->
        App aziendali -> "Microsoft Graph Command Line Tools" -> Autorizzazioni -> Concedi
        consenso amministratore), molto piu' leggero di registrare una nuova app.

        Per questo, su un tenant Delegated senza connessione gia' attiva, questa funzione
        NON tenta il login da sola: lancia subito un errore chiaro, a meno che non venga
        chiamata esplicitamente con -AllowInteractive (uso riservato al pulsante "Connetti
        Intune" nella GUI - click esplicito e consapevole di un'attesa possibile, mai
        dentro un flusso composto automatico che bloccherebbe il server senza preavviso -
        esattamente l'incidente reale del 15/08/2026, prima di questo fix).

        Il flag $script:M365OpsIntuneConnected NON viene mai considerato attendibile da
        solo: ogni volta (anche quando dice gia' connesso) si verifica DAL VIVO con
        Test-M365OpsIntuneAuthValid che $Global:AuthenticationHeader sia davvero valido e
        risolva al tenant attivo - bug reale osservato il 15/08/2026, una connessione
        ritenuta valida ha lasciato l'header vuoto/inutilizzabile, scoperto solo a meta' di
        New-M365OpsWin32App con un warning criptico del modulo invece che con un errore
        chiaro subito.
    #>
    param([switch]$Force, [switch]$AllowInteractive)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    if ($script:M365OpsIntuneConnected -and -not $Force) {
        if (Test-M365OpsIntuneAuthValid) { return }
        # Il flag mentiva (vedi .SYNOPSIS) - si autocorregge e si procede come se non
        # fossimo mai stati connessi, invece di lasciare che il problema emerga piu' tardi
        # dentro un cmdlet del modulo con un messaggio che non spiega la causa reale.
        $script:M365OpsIntuneConnected = $false
        Write-M365OpsLog "Connect-M365OpsIntune: connessione ritenuta valida ma la verifica dal vivo e' fallita - forzo una riconnessione." -Level Warn
    }

    if ($script:M365OpsContext.AuthMode -eq 'Delegated' -and -not $AllowInteractive) {
        throw "Sessione Intune non ancora attiva per questo tenant delegato. Il server non avvia mai un login interattivo da solo (bloccherebbe l'intera app per tutti, essendo a thread singolo, e IntuneWin32App non supporta un token gia' pronto come Exchange) - vai al tab Tenant, sezione Intune, e clicca 'Connetti Intune (browser)' per farlo esplicitamente, poi riprova a pacchettizzare."
    }

    Import-Module IntuneWin32App -ErrorAction Stop

    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        # Arriva qui SOLO con -AllowInteractive esplicito (vedi sopra) - blocca davvero,
        # ma per una scelta diretta e consapevole dell'utente, non a sua insaputa. -Interactive
        # (non -DeviceCode, vedi .SYNOPSIS: quest'ultimo e' rotto su PS7) apre il browser di
        # sistema con selezione account esplicita. ClientID: riusa il client pubblico
        # Microsoft gia' funzionante per Graph, nessuna App Registration nuova richiesta a
        # meno di un problema di consenso admin.
        Connect-MSIntuneGraph -TenantID $script:M365OpsContext.TenantId -ClientID $script:M365OpsDeviceCodeClientId -Interactive | Out-Null
    }
    else {
        if (-not $script:M365OpsContext.SecretEnvVar) {
            throw "Il profilo '$($script:M365OpsContext.Name)' non ha un SecretEnvVar configurato."
        }
        $secret = Get-M365OpsSecret -Name $script:M365OpsContext.SecretEnvVar
        if (-not $secret) { throw "Secret del tenant ('$($script:M365OpsContext.SecretEnvVar)') non trovato." }
        Connect-MSIntuneGraph -TenantID $script:M365OpsContext.TenantId -ClientID $script:M365OpsContext.ClientId `
            -ClientSecret $secret | Out-Null
    }

    if (-not (Test-M365OpsIntuneAuthValid)) {
        throw "La connessione a Intune sembra essere riuscita ma la verifica successiva (chiamata a Graph con il token ottenuto) e' fallita - riprova. Se persiste, potrebbe mancare il consenso admin per questa app su questo tenant (vedi .SYNOPSIS)."
    }
    $script:M365OpsIntuneConnected = $true
}
