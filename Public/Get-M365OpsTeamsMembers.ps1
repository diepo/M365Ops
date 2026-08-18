function Get-M365OpsTeamsMembers {
    <#
    .SYNOPSIS
        Elenca i membri di UN team (GroupId da Get-M365OpsTeamsList, mai indovinato), con ruolo
        (owner/member/guest) - utile per capire chi ha diritti di ospite in un team specifico.
        Verificato dal vivo il 17/08/2026.
    #>
    param([Parameter(Mandatory)] [string]$GroupId)
    Connect-M365OpsTeams
    Get-TeamUser -GroupId $GroupId | Select-Object User, Name, Role
}
