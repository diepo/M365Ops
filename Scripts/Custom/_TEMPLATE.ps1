<#
    TEMPLATE - copia questo file, rinominalo (nome file = nome funzione, es.
    Get-M365OpsOneDriveSharingReport.ps1), e adattalo. I file che iniziano con "_" non
    vengono mai caricati - solo per esempi. Vedi README.md in questa cartella per la
    convenzione completa.
#>

function Get-M365OpsEsempioReport {
    <#
    .SYNOPSIS
        UNA RIGA chiara: cosa restituisce esattamente (non "esegue una query" - il DATO
        specifico), a chi serve, e qualunque limite/permesso non ovvio. Questa riga e'
        l'UNICA cosa che l'AI vede per decidere se e quando usare questo script - se e'
        vaga, l'AI lo user in modo sbagliato o non lo user affatto. Esempio buono:
        "Elenca i link di condivisione pubblici attivi su OneDrive per ogni utente,
        con proprietario e data di creazione - richiede il permesso Graph Sites.Read.All
        (non incluso di default, va aggiunto all'App Registration)."

    .PARAMETER Identity
        Descrizione del parametro - una per ogni parametro dichiarato sotto. L'AI usa
        questo testo per capire cosa passare, quindi sii specifico sul formato atteso
        (es. "UPN completo", "GUID", "nome esatto del gruppo").

    .NOTES
        Mode: ReadOnly
        (OBBLIGATORIO - ReadOnly se lo script legge soltanto ed e' eseguibile subito
        dall'AI senza conferma; Write se crea/modifica/elimina qualcosa - in quel caso
        l'AI puo' solo PROPORNE l'esecuzione, mai eseguirlo senza conferma esplicita
        dell'utente, stesso principio di ogni altra scrittura in questo modulo. Senza
        questo tag lo script viene ignorato, mai esposto all'AI, per sicurezza.)
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity
    )

    # Usa SEMPRE le funzioni di accesso dati gia' esistenti del modulo, mai gestire tu
    # stesso token o credenziali: cosi' lo script funziona automaticamente sia sui tenant
    # AppOnly (client credentials) sia su quelli Delegated (login utente + MFA) - vedi
    # sezione 10 della guida. Esempi:
    #
    #   Graph:     Invoke-M365OpsGraphRequest -Method GET -Path "/users/$Identity/drive"
    #   Exchange:  Connect-M365OpsExchange; Get-Mailbox -Identity $Identity
    #
    # Non usare Read-Host o altri prompt interattivi: deve essere una funzione pura,
    # parametri in ingresso, oggetti PowerShell in uscita (mai testo libero).
    #
    # Se ti serve un parametro nativo poco comune (di Get-Mailbox, New-Mailbox, ecc.), NON
    # indovinare il nome/formato: verifica prima con Invoke-M365OpsLookupMsDocs -Topic
    # "Nome-Cmdlet" (o chiedi all'AI in chat "lookup_ms_docs") - la doc reale di Microsoft
    # Learn, non la conoscenza pregressa di chi scrive lo script.

    Connect-M365OpsExchange
    Get-Mailbox -Identity $Identity | Select-Object DisplayName, PrimarySmtpAddress
}
