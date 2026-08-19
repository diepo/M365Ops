function New-M365OpsSharePointSite {
    <#
    .SYNOPSIS
        Crea un nuovo sito SharePoint Online, Team site (con gruppo Microsoft 365 associato) o
        Communication site. Nessun membro/visitatore viene aggiunto oltre l'owner indicato - usa
        Set-M365OpsSharePointSiteMember come passo separato per popolare i gruppi.
    .PARAMETER Template
        'TeamSite' (crea anche un gruppo Microsoft 365, Team-abilitabile in seguito) oppure
        'CommunicationSite' (nessun gruppo, pensato per pubblicazione/intranet).
    .PARAMETER Alias
        Solo per TeamSite: parte locale dell'indirizzo del gruppo (es. 'progetto-x' ->
        progetto-x@contoso.onmicrosoft.com). Obbligatorio per TeamSite, ignorato per
        CommunicationSite (dove invece serve -Url).
    .PARAMETER Url
        Solo per CommunicationSite: URL completo del sito da creare. Ignorato per TeamSite
        (l'URL viene derivato automaticamente da -Alias).
    #>
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [ValidateSet('TeamSite', 'CommunicationSite')] [string]$Template,
        [string]$Owner,
        [string]$Alias,
        [string]$Url,
        [switch]$IsPublic
    )
    Connect-M365OpsSharePoint

    # -ErrorAction Stop su entrambi i rami: stesso bug di errore non terminante ignorato in
    # silenzio gia' trovato su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026), qui
    # sul modulo PnP.PowerShell.
    if ($Template -eq 'TeamSite') {
        if (-not $Alias) { throw "TeamSite richiede -Alias (parte locale dell'indirizzo del gruppo, es. 'progetto-x')." }
        $params = @{ Type = 'TeamSite'; Title = $Title; Alias = $Alias; ErrorAction = 'Stop' }
        if ($Owner) { $params.Owner = $Owner }
        if ($IsPublic) { $params.IsPublic = $true }
        $siteUrl = New-PnPSite @params
    }
    else {
        if (-not $Url) { throw "CommunicationSite richiede -Url (indirizzo completo del sito da creare)." }
        $params = @{ Type = 'CommunicationSite'; Title = $Title; Url = $Url; ErrorAction = 'Stop' }
        if ($Owner) { $params.Owner = $Owner }
        $siteUrl = New-PnPSite @params
    }

    Write-Host "Sito SharePoint creato: $siteUrl" -ForegroundColor Green
    [pscustomobject]@{ Title = $Title; Template = $Template; Url = $siteUrl; Owner = $Owner }
}
