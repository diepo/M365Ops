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
        # BUG REALE segnalato dal vivo il 25/08/2026 su una macchina di test nuova: un profilo
        # AppOnly configurato SOLO con certificato (nessun SecretEnvVar - esattamente come
        # Exchange/Teams/SharePoint, che accettano entrambi in alternativa, vedi Set-M365OpsTenant)
        # falliva qui con "non ha un SecretEnvVar configurato", anche se un certificato era gia'
        # configurato e gia' funzionante per Exchange sullo stesso profilo. Causa: questa funzione
        # richiedeva SEMPRE il secret, mai il certificato come alternativa - unica cmdlet di
        # connessione del progetto con questa asimmetria (Connect-MSIntuneGraph supporta
        # -ClientCert da sempre, verificato dal vivo sul modulo installato: accetta un oggetto
        # X509Certificate2, non solo il thumbprint). Corretto usando lo stesso certificato di
        # Exchange (ExchangeCertThumbprint) quando il secret non e' configurato, stesso principio
        # gia' usato ovunque nel progetto (un solo materiale segreto da gestire per tutto
        # App-only) - cercato in Cert:\CurrentUser\My poi Cert:\LocalMachine\My, stessi due store
        # gia' provati da Connect-ExchangeOnline -CertificateThumbprint (vedi anche
        # New-M365OpsCertificateAssertion.ps1, stesso pattern di lookup).
        if ($script:M365OpsContext.SecretEnvVar) {
            $secret = Get-M365OpsSecret -Name $script:M365OpsContext.SecretEnvVar
            if (-not $secret) { throw "Secret del tenant ('$($script:M365OpsContext.SecretEnvVar)') non trovato." }
            Connect-MSIntuneGraph -TenantID $script:M365OpsContext.TenantId -ClientID $script:M365OpsContext.ClientId `
                -ClientSecret $secret | Out-Null
        }
        elseif ($script:M365OpsContext.ExchangeCertThumbprint) {
            $thumbprint = $script:M365OpsContext.ExchangeCertThumbprint
            $cert = Get-Item "Cert:\CurrentUser\My\$thumbprint" -ErrorAction SilentlyContinue
            if (-not $cert) { $cert = Get-Item "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue }
            if (-not $cert) {
                throw "Certificato con thumbprint '$thumbprint' non trovato ne' in Cert:\CurrentUser\My ne' in Cert:\LocalMachine\My su questo PC - stesso certificato gia' usato per Exchange deve essere installato qui."
            }
            Connect-MSIntuneGraph -TenantID $script:M365OpsContext.TenantId -ClientID $script:M365OpsContext.ClientId `
                -ClientCert $cert | Out-Null
        }
        else {
            throw "Il profilo '$($script:M365OpsContext.Name)' non ha ne' un SecretEnvVar ne' un ExchangeCertThumbprint configurato - Intune App-only richiede uno dei due (stesso principio di Exchange/Teams/SharePoint). Usa Set-M365OpsTenant per impostarne uno."
        }
    }

    if (-not (Test-M365OpsIntuneAuthValid)) {
        throw "La connessione a Intune sembra essere riuscita ma la verifica successiva (chiamata a Graph con il token ottenuto) e' fallita - riprova. Se persiste, potrebbe mancare il consenso admin per questa app su questo tenant (vedi .SYNOPSIS)."
    }
    $script:M365OpsIntuneConnected = $true
}
