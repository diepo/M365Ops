function Find-M365OpsUser {
    <#
    .SYNOPSIS
        Cerca utenti per nome visualizzato (non serve conoscere lo UPN esatto).
        Usata quando in chat viene indicato un nome invece di un indirizzo email.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name
    )

    $escaped = $Name.Trim().Replace("'", "''")
    $result = (Invoke-M365OpsGraphRequest -Method GET -Path "/users?`$filter=startswith(displayName,'$escaped')&`$select=id,displayName,userPrincipalName&`$top=5").value
    return $result
}
