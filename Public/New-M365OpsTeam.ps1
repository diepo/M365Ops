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

    $params = @{ DisplayName = $DisplayName; Visibility = $Visibility }
    if ($Description) { $params.Description = $Description }
    if ($Owner) { $params.Owner = $Owner }

    $team = New-Team @params
    Write-Host "Team creato: $($team.DisplayName) ($($team.GroupId))" -ForegroundColor Green
    $team | Select-Object DisplayName, GroupId, Visibility
}
