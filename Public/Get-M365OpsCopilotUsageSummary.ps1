function Get-M365OpsCopilotUsageSummary {
    <#
    .SYNOPSIS
        Numero aggregato di utenti abilitati/attivi per Microsoft 365 Copilot, per app -
        la vista "riassunto" dello stesso report mostrato in "Report > Utilizzo >
        Microsoft 365 Copilot" nell'admin center (l'equivalente aggregato di
        Get-M365OpsCopilotUsageReport, che invece e' per singolo utente). Endpoint Graph
        v1.0 (GA, non beta) - restituisce SEMPRE CSV, non JSON (comportamento documentato,
        non un bug: vedi Microsoft Learn per copilotReportRoot:
        getMicrosoft365CopilotUserCountSummary).
    .PARAMETER Period
        Finestra di aggregazione in giorni precedenti: D7, D30, D90, D180 o ALL (default D30).
    .NOTES
        Mode: Read
        Permesso Graph richiesto: Reports.Read.All (Application) - stesso permesso di
        Get-M365OpsCopilotUsageReport, NON ancora presente sull'app registration di test
        usata in questa sessione (confermato dal vivo con 403 "Invalid permission." su
        quella cmdlet gemella) - va aggiunto in Entra ID > App Registration > API
        permissions > Add a permission > Microsoft Graph > Application permissions >
        Reports.Read.All > Grant admin consent (sezione 4.2 della guida).
    #>
    param(
        [ValidateSet('D7', 'D30', 'D90', 'D180', 'ALL')]
        [string]$Period = 'D30'
    )

    $raw = Invoke-M365OpsGraphRequest -Method GET -Path "/copilot/reports/getMicrosoft365CopilotUserCountSummary(period='$Period')"

    # Stessa normalizzazione CSV di Get-M365OpsCopilotUsageReport - vedi li' per il dettaglio
    # del perche' (risposta v1.0 sempre CSV, mai JSON, indipendentemente da $format).
    $csvText = if ($raw -is [string]) { $raw } else { ($raw -join "`n") }
    if (-not $csvText -or -not $csvText.Trim()) { return @() }

    $rows = @(ConvertFrom-Csv -InputObject $csvText)
    @(foreach ($r in $rows) {
        [pscustomobject]@{
            ReportRefreshDate         = $r.'Report Refresh Date'
            ReportPeriodDays          = $r.'Report Period'
            TeamsEnabledUsers         = $r.'Microsoft Teams Enabled Users'
            TeamsActiveUsers          = $r.'Microsoft Teams Active Users'
            WordEnabledUsers          = $r.'Word Enabled Users'
            WordActiveUsers           = $r.'Word Active Users'
            PowerPointEnabledUsers    = $r.'PowerPoint Enabled Users'
            PowerPointActiveUsers     = $r.'PowerPoint Active Users'
            OutlookEnabledUsers       = $r.'Outlook Enabled Users'
            OutlookActiveUsers        = $r.'Outlook Active Users'
            ExcelEnabledUsers         = $r.'Excel Enabled Users'
            ExcelActiveUsers          = $r.'Excel Active Users'
            OneNoteEnabledUsers       = $r.'OneNote Enabled Users'
            OneNoteActiveUsers        = $r.'OneNote Active Users'
            LoopEnabledUsers          = $r.'Loop Enabled Users'
            LoopActiveUsers           = $r.'Loop Active Users'
            AnyAppEnabledUsers        = $r.'Any App Enabled Users'
            AnyAppActiveUsers         = $r.'Any App Active Users'
            CopilotChatEnabledUsers   = $r.'Copilot Chat Enabled Users'
            CopilotChatActiveUsers    = $r.'Copilot Chat Active Users'
        }
    })
}
