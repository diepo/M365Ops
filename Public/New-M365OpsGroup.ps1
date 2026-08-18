function New-M365OpsGroup {
    <#
    .SYNOPSIS
        Crea un gruppo di sicurezza Entra ID, opzionalmente con membri iniziali (UPN).
        Un fallimento nell'aggiunta di UN membro (es. UPN inesistente/malformato) non fa
        fallire l'intera funzione: il gruppo a quel punto esiste gia' su Entra ID, quindi
        lasciar propagare un'eccezione generica lo nasconderebbe al chiamante - un eventuale
        retry (automatico via Invoke-M365OpsActionRecovery, o manuale dell'utente) creerebbe
        un SECONDO gruppo duplicato invece di limitarsi a correggere il membro (bug reale
        individuato in revisione). Gli errori sui singoli membri vengono invece raccolti
        nella proprieta' MemberErrors del gruppo restituito.
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [string[]]$MemberUpn
    )

    $mailNickname = ($DisplayName -replace '[^a-zA-Z0-9]', '')
    $body = @{
        displayName     = $DisplayName
        mailEnabled     = $false
        mailNickname    = $mailNickname
        securityEnabled = $true
    }
    # Graph rifiuta una description vuota (richiede 1-1024 caratteri): la si aggiunge solo se valorizzata.
    if ($Description) { $body.description = $Description }

    $group = Invoke-M365OpsGraphRequest -Method POST -Path "/groups" -Body $body
    Write-Host "Gruppo creato: $($group.displayName) ($($group.id))" -ForegroundColor Green

    $memberErrors = @()
    foreach ($upn in $MemberUpn) {
        try {
            $user = Invoke-M365OpsGraphRequest -Method GET -Path "/users/$upn`?`$select=id"
            $memberBody = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.id)" }

            # Un gruppo appena creato non e' sempre immediatamente visibile a tutte le
            # repliche di Graph (eventual consistency) - un 404 qui subito dopo la
            # creazione e' normale, non un errore reale. Riprova con backoff prima di
            # arrendersi su QUESTO membro (non sull'intera creazione, vedi .SYNOPSIS).
            $maxAttempts = 5
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    Invoke-M365OpsGraphRequest -Method POST -Path "/groups/$($group.id)/members/`$ref" -Body $memberBody | Out-Null
                    Write-Host "  + membro: $upn" -ForegroundColor Green
                    break
                }
                catch {
                    if ($attempt -eq $maxAttempts) { throw }
                    Start-Sleep -Seconds $attempt
                }
            }
        }
        catch {
            $memberErrors += "$upn`: $($_.Exception.Message)"
        }
    }

    if ($memberErrors.Count -gt 0) {
        $group | Add-Member -MemberType NoteProperty -Name 'MemberErrors' -Value $memberErrors -Force
    }
    $group
}
