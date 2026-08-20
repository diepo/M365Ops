function Get-M365OpsCopilotUsageReport {
    <#
    .SYNOPSIS
        Report per-utente di utilizzo Microsoft 365 Copilot: ultima attivita' complessiva e
        per singola app (Teams/Word/Excel/PowerPoint/Outlook/OneNote/Loop/Copilot Chat) -
        gli stessi dati mostrati in "Report > Utilizzo > Microsoft 365 Copilot" nell'admin
        center. Endpoint Graph v1.0 (GA, non beta) - restituisce SEMPRE CSV, non JSON
        (comportamento documentato, non un bug: vedi Microsoft Learn per
        copilotReportRoot: getMicrosoft365CopilotUsageUserDetail), quindi qui viene
        convertito con ConvertFrom-Csv e le colonne rinominate in PascalCase per coerenza
        con lo stile del resto del progetto.
    .PARAMETER Period
        Finestra di aggregazione in giorni precedenti: D7, D30, D90, D180 o ALL (default D30).
    .NOTES
        Mode: Read
        Permesso Graph richiesto: Reports.Read.All (Application) - NON ancora presente
        sull'app registration di test usata in questa sessione, confermato dal vivo con una
        chiamata reale che ha restituito 403 "S2SUnauthorized: Invalid permission." (non
        un'ipotesi da documentazione). Va aggiunto in Entra ID > App Registration > API
        permissions > Add a permission > Microsoft Graph > Application permissions >
        Reports.Read.All > Grant admin consent - vedi sezione 4.2 della guida. Funziona
        identico sia in modalita' App-only sia Delegata (nessuna delle due limitazioni gia'
        viste per altre aree Copilot, es. Copilot Policy Settings, che sono solo Delegate).
        Restituisce dati SOLO per utenti con licenza Microsoft 365 Copilot assegnata - per
        l'utilizzo di Copilot Chat non licenziato, l'admin center ha un report separato non
        raggiungibile da questa API.
    #>
    param(
        [ValidateSet('D7', 'D30', 'D90', 'D180', 'ALL')]
        [string]$Period = 'D30'
    )

    $raw = Invoke-M365OpsGraphRequest -Method GET -Path "/copilot/reports/getMicrosoft365CopilotUsageUserDetail(period='$Period')"

    # La risposta e' un flusso CSV (application/octet-stream) - Invoke-RestMethod puo'
    # restituirlo come stringa unica o come array di righe a seconda della versione di
    # PowerShell/.NET, quindi normalizzato qui prima di passarlo a ConvertFrom-Csv.
    $csvText = if ($raw -is [string]) { $raw } else { ($raw -join "`n") }
    if (-not $csvText -or -not $csvText.Trim()) { return @() }

    $rows = @(ConvertFrom-Csv -InputObject $csvText)
    @(foreach ($r in $rows) {
        [pscustomobject]@{
            ReportRefreshDate                = $r.'Report Refresh Date'
            UserPrincipalName                = $r.'User Principal Name'
            DisplayName                      = $r.'Display Name'
            LastActivityDate                 = $r.'Last Activity Date'
            CopilotChatLastActivityDate      = $r.'Copilot Chat Last Activity Date'
            TeamsCopilotLastActivityDate     = $r.'Microsoft Teams Copilot Last Activity Date'
            WordCopilotLastActivityDate      = $r.'Word Copilot Last Activity Date'
            ExcelCopilotLastActivityDate     = $r.'Excel Copilot Last Activity Date'
            PowerPointCopilotLastActivityDate = $r.'PowerPoint Copilot Last Activity Date'
            OutlookCopilotLastActivityDate   = $r.'Outlook Copilot Last Activity Date'
            OneNoteCopilotLastActivityDate   = $r.'OneNote Copilot Last Activity Date'
            LoopCopilotLastActivityDate      = $r.'Loop Copilot Last Activity Date'
            ReportPeriodDays                 = $r.'Report Period'
        }
    })
}
