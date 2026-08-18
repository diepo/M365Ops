function Get-M365OpsTenantAllowBlockList {
    <#
    .SYNOPSIS
        Elenca le voci della Tenant Allow/Block List (mittenti, URL, hash di file, IP
        esplicitamente consentiti o bloccati a livello di tenant). Senza -ListType interroga
        tutti e 4 i tipi e li unisce in un unico elenco, distinti dalla colonna ListType -
        lista vuota per un tipo e' un risultato legittimo (nessuna eccezione configurata).
    #>
    param(
        [ValidateSet('Sender', 'Url', 'FileHash', 'IP')] [string]$ListType
    )
    Connect-M365OpsExchange

    $types = if ($ListType) { @($ListType) } else { @('Sender', 'Url', 'FileHash', 'IP') }
    foreach ($t in $types) {
        Get-TenantAllowBlockListItems -ListType $t |
            Select-Object @{N = 'ListType'; E = { $t } }, Value, Action, ExpirationDate, LastModifiedDateTime, Notes
    }
}
