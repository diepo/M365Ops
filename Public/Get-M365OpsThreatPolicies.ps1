function Get-M365OpsThreatPolicies {
    <#
    .SYNOPSIS
        Elenca i criteri Safe Links e Safe Attachments (Microsoft Defender for Office 365) in
        un'unica lista, distinti dalla colonna PolicyType - richiede licenza Defender for
        Office 365 (P1 o P2), su tenant senza quella licenza Get-SafeLinksPolicy/
        Get-SafeAttachmentPolicy restituiscono lista vuota, non un errore.
    #>
    Connect-M365OpsExchange

    $safeLinks = Get-SafeLinksPolicy | ForEach-Object {
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

    $safeAttachments = Get-SafeAttachmentPolicy | ForEach-Object {
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

    @($safeLinks) + @($safeAttachments)
}
