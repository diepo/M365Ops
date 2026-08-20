function Get-M365OpsInboundConnector {
    <#
    .SYNOPSIS
        Elenca i connettori Inbound (regole su come il tenant ACCETTA posta in ingresso da
        fonti specifiche - tipicamente usati per integrare un gateway di sicurezza email di
        terze parti o instradare posta da un'organizzazione on-premise in scenari ibridi).
    .NOTES
        Mode: ReadOnly

        BUG STRUTTURALE trovato dal vivo il 21/08/2026, richiesto dall'utente ("puoi fare
        test in modalita' delegata?" sul limite RBAC apparente di sezione 6.4): questa
        funzione (insieme a New-/Set-/Remove-) prima chiamava Get-ReceiveConnector, un
        cmdlet ESCLUSIVO di Exchange on-premises - non e' MAI esistito in Exchange Online,
        indipendentemente da qualunque ruolo RBAC. "term not recognized" era quindi
        prevedibile fin dall'inizio, non un limite di permessi: verificato dal vivo che
        l'errore persiste identico sia in App-only sia in Delegated con un utente reale
        membro completo di "Organization Management" (praticamente ogni ruolo Exchange
        esistente) - se fosse stato un problema di RBAC, un membro di Organization Management
        avrebbe dovuto riuscire. La discussione precedente sulla sezione 6.4 (ruolo directory
        Entra + ruolo RBAC Exchange verificati ma cmdlet ancora assente) resta valida per
        New-AcceptedDomain (un cmdlet Exchange Online reale, confermato funzionante in
        Delegated lo stesso giorno) ma NON si applicava a questo caso - due bug diversi
        scambiati per lo stesso fenomeno perche' producevano lo stesso identico messaggio di
        errore testuale.
        Il vero cmdlet Exchange Online per questo scopo e' Get-InboundConnector - nome
        diverso, non un alias. Verificato su documentazione ufficiale Microsoft, non a
        memoria: la pagina di Get-ReceiveConnector dichiara esplicitamente "This cmdlet is
        available only in on-premises Exchange"
        (learn.microsoft.com/powershell/module/exchangepowershell/get-receiveconnector).
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    if ($Identity) { Get-InboundConnector -Identity $Identity }
    else { Get-InboundConnector | Select-Object Name, Enabled, ConnectorType, SenderDomains }
}
