function Set-M365OpsTeam {
    <#
    .SYNOPSIS
        Modifica un Team esistente (nome, descrizione, visibilita', archiviazione). Passa solo
        i parametri da cambiare - quelli omessi restano invariati.
    .PARAMETER GroupId
        ID del gruppo Microsoft 365 associato al Team (da Get-M365OpsTeamsList) - mai indovinato.
    #>
    param(
        [Parameter(Mandatory)] [string]$GroupId,
        [string]$DisplayName,
        [string]$Description,
        [ValidateSet('Private', 'Public')] [string]$Visibility,
        [Nullable[bool]]$Archived
    )
    Connect-M365OpsTeams

    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - il modulo MicrosoftTeams
    # e' gia' noto in questo progetto per errori non terminanti (sezione 17.11.1 della guida).
    $params = @{ GroupId = $GroupId; ErrorAction = 'Stop' }
    if ($DisplayName) { $params.DisplayName = $DisplayName }
    if ($Description) { $params.Description = $Description }
    if ($Visibility) { $params.Visibility = $Visibility }
    if ($null -ne $Archived) { $params.Archived = $Archived }

    Set-Team @params
    Write-Host "Team $GroupId aggiornato." -ForegroundColor Green
    Get-Team -GroupId $GroupId | Select-Object DisplayName, GroupId, Visibility, Archived
}
