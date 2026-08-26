function Get-M365OpsThreatPolicies {
    <#
    .SYNOPSIS
        Elenca i criteri Safe Links e Safe Attachments (Microsoft Defender for Office 365) in
        un'unica lista, distinti dalla colonna PolicyType - richiede licenza Defender for
        Office 365 (P1 o P2), su tenant senza quella licenza Get-SafeLinksPolicy/
        Get-SafeAttachmentPolicy restituiscono lista vuota, non un errore.
    #>
    Connect-M365OpsExchange

    # Safe Links e Safe Attachments sono due criteri INDIPENDENTI l'uno dall'altro (26/08/2026,
    # stesso schema gia' corretto piu' volte in questa maratona - v0.10.1/v0.10.2/v0.10.6): la
    # nota nel .SYNOPSIS copre solo il caso "tenant senza licenza Defender" (lista vuota, non un
    # errore), ma non un fallimento transitorio (throttling, sessione Exchange che scade a meta')
    # su UNA delle due chiamate - prima di questo fix, un errore su Get-SafeLinksPolicy usciva
    # dall'intera funzione PRIMA di raggiungere Get-SafeAttachmentPolicy, completamente
    # indipendente, perdendo anche quel risultato. Isolate cosi' un fallimento su un tipo di
    # criterio non nasconde piu' l'altro.
    $safeLinks = try {
        Get-SafeLinksPolicy -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                PolicyType               = "Safe Links"
                Name                     = $_.Name
                IsDefault                = $_.IsDefault
                Enable                   = $null
                Action                   = $null
                EnableSafeLinksForEmail  = $_.EnableSafeLinksForEmail
                EnableSafeLinksForTeams  = $_.EnableSafeLinksForTeams
                EnableSafeLinksForOffice = $_.EnableSafeLinksForOffice
                ScanUrls                 = $_.ScanUrls
                TrackClicks              = $_.TrackClicks
                DeliverMessageAfterScan  = $_.DeliverMessageAfterScan
            }
        }
    }
    catch {
        [pscustomobject]@{ PolicyType = 'Safe Links'; Name = "Lettura fallita: $($_.Exception.Message)" }
    }

    $safeAttachments = try {
        Get-SafeAttachmentPolicy -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                PolicyType               = "Safe Attachments"
                Name                     = $_.Name
                IsDefault                = $_.IsDefault
                Enable                   = $_.Enable
                Action                   = $_.Action
                EnableSafeLinksForEmail  = $null
                EnableSafeLinksForTeams  = $null
                EnableSafeLinksForOffice = $null
                ScanUrls                 = $null
                TrackClicks              = $null
                DeliverMessageAfterScan  = $null
            }
        }
    }
    catch {
        [pscustomobject]@{ PolicyType = 'Safe Attachments'; Name = "Lettura fallita: $($_.Exception.Message)" }
    }

    @($safeLinks) + @($safeAttachments)
}
