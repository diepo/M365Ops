function Get-M365OpsTeamsChannels {
    <#
    .SYNOPSIS
        Elenca i canali di UN team (GroupId da Get-M365OpsTeamsList, mai indovinato). Verificato
        dal vivo il 17/08/2026.
    #>
    param([Parameter(Mandatory)] [string]$GroupId)
    Connect-M365OpsTeams
    Get-TeamChannel -GroupId $GroupId | Select-Object DisplayName, Id, Description, MembershipType
}
