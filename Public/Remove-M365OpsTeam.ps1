function Remove-M365OpsTeam {
    <#
    .SYNOPSIS
        Rimuove un Team (e il gruppo Microsoft 365 associato, con tutti i suoi contenuti -
        canali, file, chat). Irreversibile senza un ripristino del gruppo dal cestino Entra ID
        entro 30 giorni.
    .PARAMETER GroupId
        ID del gruppo Microsoft 365 associato al Team (da Get-M365OpsTeamsList) - mai indovinato.
    #>
    param([Parameter(Mandatory)] [string]$GroupId)
    Connect-M365OpsTeams

    $team = Get-Team -GroupId $GroupId
    Remove-Team -GroupId $GroupId

    Write-Host "Team rimosso: $($team.DisplayName) ($GroupId)" -ForegroundColor Green
    [pscustomobject]@{ DisplayName = $team.DisplayName; GroupId = $GroupId; Removed = $true }
}
