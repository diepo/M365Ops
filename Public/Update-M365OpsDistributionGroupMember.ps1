function Update-M365OpsDistributionGroupMember {
    <#
    .SYNOPSIS
        SOSTITUISCE l'intera lista membri di un gruppo con quella fornita - non e' un
        aggiunta incrementale (per quello vedi Add-/Remove-M365OpsDistributionGroupMember).
        Chiunque non sia nell'elenco passato viene rimosso dal gruppo. Utile per
        sincronizzare la membership da una fonte esterna (es. un CSV), rischioso se usato
        a meta' di una lista pensando che aggiunga soltanto. -Members accetta anche
        $null/vuoto per svuotare completamente il gruppo (uso legittimo, non un errore).
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [string[]]$Members
    )
    # Bug reale trovato dal vivo il 18/08/2026 (diagnosi automatica dell'app): -Members e'
    # Mandatory ma senza AllowNull/AllowEmptyCollection PowerShell rifiuta il binding di $null
    # PRIMA che la funzione parta - "svuota il gruppo" (un uso esplicitamente documentato sopra)
    # falliva quindi sempre con un errore di binding parametro invece di eseguire la sostituzione
    # con lista vuota. Normalizzato qui perche' il nativo Update-DistributionGroupMember accetta
    # -Members $null per svuotare, ma il wrapper lo bloccava prima di arrivarci.
    if ($null -eq $Members) { $Members = [string[]]@() }
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in Set-M365OpsDistributionGroup.ps1 (bug reale 18/08/2026).
    Update-DistributionGroupMember -Identity $Identity -Members $Members -Confirm:$false -ErrorAction Stop
    Write-Host "Membership del gruppo '$Identity' sostituita con $($Members.Count) membri." -ForegroundColor Green
    Get-DistributionGroupMember -Identity $Identity -ResultSize Unlimited | Select-Object DisplayName, PrimarySmtpAddress
}
