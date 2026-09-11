function Get-M365OpsExchangeRecipientDetail {
    <#
    .SYNOPSIS
        Restituisce l'oggetto COMPLETO (tutte le proprieta' native, non un sottoinsieme
        curato a mano) di UN destinatario Exchange non-mailbox: gruppo di distribuzione
        (anche mail-enabled security group, stesso cmdlet nativo - la differenza e' solo nel
        campo GroupType del risultato), gruppo di distribuzione dinamico, mail contact, o
        mail user. Per le MAILBOX (di ogni tipo: utente, condivisa, risorsa/sala/attrezzatura
        - sono tutte lo stesso oggetto Exchange, RecipientTypeDetails diverso) vedi invece
        Get-M365OpsMailboxDetail, gia' generale per quel tipo di oggetto dall'11/09/2026.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('DistributionGroup', 'DynamicDistributionGroup', 'MailContact', 'MailUser')]
        [string]$ObjectType,
        [Parameter(Mandatory)] [string]$Identity
    )
    Connect-M365OpsExchange
    # Aggiunta l'11/09/2026, generalizzazione richiesta esplicitamente dall'utente dopo
    # Get-M365OpsMailboxDetail: "questa cosa va estesa in generale a tutta la nostra sfera -
    # distributiongroup, shared, resources, room, teams etc" - un tool per QUALUNQUE campo di
    # QUESTI tipi di oggetto, invece di continuare a curare a mano un sottoinsieme di proprieta'
    # per ognuno (vedi Get-M365OpsDistributionGroups/Get-M365OpsMailContacts/ecc. per l'elenco,
    # che restano per le LISTE - questo e' per il DETTAGLIO completo di UN oggetto specifico).
    # Un solo switch invece di 4 file quasi identici - stesso principio "un solo posto per una
    # regola condivisa" gia' seguito altrove in questo progetto.
    switch ($ObjectType) {
        'DistributionGroup'        { Get-DistributionGroup -Identity $Identity -ErrorAction Stop }
        'DynamicDistributionGroup' { Get-DynamicDistributionGroup -Identity $Identity -ErrorAction Stop }
        'MailContact'              { Get-MailContact -Identity $Identity -ErrorAction Stop }
        'MailUser'                 { Get-MailUser -Identity $Identity -ErrorAction Stop }
    }
}
