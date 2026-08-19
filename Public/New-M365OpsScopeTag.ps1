function New-M365OpsScopeTag {
    <#
    .SYNOPSIS
        Crea uno Scope Tag Intune (roleScopeTag) - risorsa esistente solo in Graph beta,
        verificato dal vivo su Microsoft Learn il 19/08/2026 (nessuna pagina v1.0 per questa
        risorsa). Per assegnare uno scope tag esistente a un oggetto (app, criterio, ecc.) usa
        il parametro -ScopeTagNames/-RoleScopeTagIds gia' presente sui cmdlet di creazione
        pertinenti; questo cmdlet serve solo a creare/gestire i tag stessi.
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = ""
    )
    $body = @{ displayName = $DisplayName; description = $Description }
    $tag = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/roleScopeTags" -Body $body -Beta
    Write-Host "Scope Tag creato: $($tag.displayName) ($($tag.id))" -ForegroundColor Green
    $tag
}
