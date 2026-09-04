function Get-M365OpsMailboxPermissions {
    <#
    .SYNOPSIS
        Restituisce i permessi (FullAccess, SendAs, SendOnBehalf) su una mailbox specifica.
        Dato Exchange Online, non disponibile via Graph. Ogni riga FullAccess/SendAs include
        anche TrusteeType ('User'/'Group'/'Unknown') - richiesto esplicitamente dall'utente
        il 31/08/2026 ("anche se la grant e' di un utente o di un gruppo") per distinguere
        senza tentativi impliciti se un permesso e' assegnato direttamente o tramite gruppo
        (rilevante soprattutto per FullAccess: un grant a un GRUPPO non abilita mai
        l'AutoMapping di Outlook per i suoi membri, limite reale di Exchange - vedi
        Get-M365OpsFullAccessAutoMapPlan).
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity
    )
    Connect-M365OpsExchange

    # Un'unica risoluzione per trustee (Get-Recipient copre QUALUNQUE tipo: utente, mail
    # user, gruppo mail-enabled di ogni tipo, gruppo dinamico, gruppo M365) invece di un
    # tentativo implicito (es. provare Get-M365OpsDistributionGroupMembers e vedere se
    # fallisce) - piu' esplicito, un'unica chiamata per identita', nessuna ambiguita'.
    # RecipientTypeDetails contiene sempre la sottostringa "Group" per ogni variante di
    # gruppo (MailUniversalSecurityGroup, MailUniversalDistributionGroup,
    # MailNonUniversalGroup, DynamicDistributionGroup, GroupMailbox per i gruppi M365) - mai
    # per un utente/mail user/mailbox di risorsa, quindi un match su quella sottostringa
    # basta a classificare senza mantenere un elenco dei valori esatti.
    $trusteeTypeCache = @{}
    function Resolve-M365OpsTrusteeType {
        param([string]$TrusteeName)
        if ($trusteeTypeCache.ContainsKey($TrusteeName)) { return $trusteeTypeCache[$TrusteeName] }
        $type = try {
            $r = Get-Recipient -Identity $TrusteeName -ErrorAction Stop
            if ($r.RecipientTypeDetails -match 'Group') { 'Group' } else { 'User' }
        } catch { 'Unknown' }
        $trusteeTypeCache[$TrusteeName] = $type
        return $type
    }

    $fullAccess = Get-EXOMailboxPermission -Identity $Identity |
        Where-Object { $_.User -notlike "NT AUTHORITY\*" -and $_.IsInherited -eq $false } |
        Select-Object @{n = 'User'; e = { $_.User.ToString() } }, @{n = 'Rights'; e = { $_.AccessRights -join ',' } }, @{n = 'Type'; e = { 'FullAccess' } }, @{n = 'TrusteeType'; e = { Resolve-M365OpsTrusteeType -TrusteeName $_.User.ToString() } }

    $sendAs = Get-EXORecipientPermission -Identity $Identity |
        Where-Object { $_.Trustee -notlike "NT AUTHORITY\*" } |
        Select-Object @{n = 'User'; e = { $_.Trustee.ToString() } }, @{n = 'Rights'; e = { $_.AccessRights -join ',' } }, @{n = 'Type'; e = { 'SendAs' } }, @{n = 'TrusteeType'; e = { Resolve-M365OpsTrusteeType -TrusteeName $_.Trustee.ToString() } }

    $mailbox = Get-EXOMailbox -Identity $Identity -Properties GrantSendOnBehalfTo
    $sendOnBehalf = $mailbox.GrantSendOnBehalfTo | ForEach-Object {
        [pscustomobject]@{ User = $_; Rights = 'SendOnBehalf'; Type = 'SendOnBehalf'; TrusteeType = (Resolve-M365OpsTrusteeType -TrusteeName $_) }
    }

    @($fullAccess) + @($sendAs) + @($sendOnBehalf)
}
