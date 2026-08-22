function New-M365OpsTeam {
    <#
    .SYNOPSIS
        Crea un nuovo Team Microsoft Teams (e il gruppo Microsoft 365 associato).
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description,
        [ValidateSet('Private', 'Public')] [string]$Visibility = 'Private',
        [string]$Owner
    )
    Connect-M365OpsTeams

    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui (il modulo
    # MicrosoftTeams e' gia' noto in questo progetto per errori non terminanti, sezione
    # 17.11.1 della guida), trovato dal vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ DisplayName = $DisplayName; Visibility = $Visibility; ErrorAction = 'Stop' }
    if ($Description) { $params.Description = $Description }
    if ($Owner) { $params.Owner = $Owner }

    $team = New-Team @params
    Write-Host "Team creato: $($team.DisplayName) ($($team.GroupId))" -ForegroundColor Green
    $team | Select-Object DisplayName, GroupId, Visibility
}
