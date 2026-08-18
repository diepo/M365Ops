function Get-M365OpsPublicFolders {
    <#
    .SYNOPSIS
        Elenca le cartelle pubbliche del tenant (se la funzionalita' e' abilitata).
    #>
    Connect-M365OpsExchange
    try {
        Get-PublicFolder -Recurse -ResultSize Unlimited | Select-Object Name, Identity, MailEnabled, ParentPath
    }
    catch {
        throw "Public Folder non disponibili o non abilitate su questo tenant: $($_.Exception.Message)"
    }
}
