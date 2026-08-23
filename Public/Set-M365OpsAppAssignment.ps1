function Set-M365OpsAppAssignment {
    <#
    .SYNOPSIS
        Assegna un'app Intune a un gruppo o a 'All Devices'. Questa e' l'unica cmdlet che
        rende un'app effettivamente attiva su dispositivi reali — usala con intenzione.

        Dal 19/08/2026 (richiesto esplicitamente dall'utente) supporta anche i parametri di
        assegnazione avanzati disponibili in portale per un'app Win32 - prima venivano
        impostati solo intent+target, tutto il resto restava sui default Intune impliciti.
        Verificato contro lo schema Graph reale (win32LobAppAssignmentSettings,
        deviceAndAppManagementAssignmentTarget) prima di scrivere questa funzione, non a
        memoria - vedi i singoli parametri per i valori ammessi.

    .PARAMETER Intent
        'available' (opzionale dal Company Portal), 'required' (installazione forzata),
        'uninstall' (disinstallazione forzata) o 'availableWithoutEnrollment' (per dispositivi
        non iscritti a Intune, raro) - i 4 valori reali dello schema Graph
        (microsoft.graph.installIntent), non solo i primi due.

    .PARAMETER TargetGroupId
        Omesso = assegna a All Devices. Valorizzato = assegna solo a quel gruppo.

        ATTENZIONE (trovata dal vivo il 23/08/2026, bug-hunt): l'azione Graph "assign" usata
        qui SOSTITUISCE SEMPRE l'intera collezione di assegnazioni dell'app, non ne aggiunge
        una - a differenza di Set-M365OpsConfigurationPolicyAssignment/
        Set-M365OpsEnrollmentConfigurationAssignment (che infatti accettano TargetGroupIds
        AL PLURALE, proprio perche' "assign" sostituisce). Chiamare questa funzione una seconda
        volta su un gruppo diverso CANCELLA silenziosamente l'assegnazione precedente invece di
        aggiungerne una seconda - per assegnare l'app a piu' gruppi/intent, serve un'unica
        chiamata con tutte le assegnazioni desiderate insieme (oggi non supportato da questa
        firma a parametro singolo: verificare/estendere prima di assumere che due chiamate
        separate funzionino come per gli altri Set-*Assignment del modulo).

    .PARAMETER FilterId
        Id di un Assignment Filter Intune GIA' esistente (creato altrove, non da questa
        funzione) - restringe/esclude l'assegnazione a un sottoinsieme del target in base a
        proprieta' del dispositivo (es. modello, OS). Richiede -FilterType.

    .PARAMETER FilterType
        'include' (assegna SOLO ai dispositivi che soddisfano il filtro) o 'exclude' (assegna
        a tutti TRANNE quelli che lo soddisfano). Ignorato se -FilterId non e' specificato.

    .PARAMETER NotificationMode
        Notifiche mostrate all'utente durante l'installazione: 'showAll' (default Intune),
        'showReboot' (solo se serve un riavvio), 'hideAll'.

    .PARAMETER RestartGracePeriodMinutes
        Minuti di preavviso prima di un riavvio forzato dopo l'installazione (se l'app lo
        richiede). Insieme a RestartCountdownDisplayMinutes/RestartSnoozeDurationMinutes
        costruisce le "Restart Settings" del portale - se NESSUNO dei tre e' specificato,
        restartSettings non viene incluso nel corpo (default Intune implicito, invariato).

    .PARAMETER AvailableDateTime / DeadlineDateTime
        Data/ora (es. "2026-09-01T22:00:00") da cui l'app diventa disponibile e/o entro cui va
        installata obbligatoriamente (per Intent=required) - le "Availability"/"Deadline" del
        portale. UseLocalTime (default $true) le interpreta nel fuso orario del dispositivo
        invece che UTC, come fa il portale di default.

    .PARAMETER DeliveryOptimizationPriority
        'notConfigured' (default) o 'foreground' (scarica con priorita' alta, utile per app
        urgenti su reti lente).

    .EXAMPLE
        Set-M365OpsAppAssignment -AppId $app.id -Intent available -TargetGroupId $group.id
        Set-M365OpsAppAssignment -AppId $app.id -Intent required   # All Devices
        Set-M365OpsAppAssignment -AppId $app.id -Intent required -TargetGroupId $group.id `
            -NotificationMode showReboot -RestartGracePeriodMinutes 1440 `
            -DeadlineDateTime "2026-09-01T22:00:00" -FilterId $filter.id -FilterType include
    #>
    param(
        [Parameter(Mandatory)] [string]$AppId,
        [Parameter(Mandatory)] [ValidateSet('available', 'required', 'uninstall', 'availableWithoutEnrollment')] [string]$Intent,
        [string]$TargetGroupId,
        [string]$FilterId,
        [ValidateSet('include', 'exclude')] [string]$FilterType,
        [ValidateSet('showAll', 'showReboot', 'hideAll')] [string]$NotificationMode,
        [int]$RestartGracePeriodMinutes,
        [int]$RestartCountdownDisplayMinutes,
        [int]$RestartSnoozeDurationMinutes,
        [string]$AvailableDateTime,
        [string]$DeadlineDateTime,
        [bool]$UseLocalTime = $true,
        [ValidateSet('notConfigured', 'foreground')] [string]$DeliveryOptimizationPriority
    )

    $target = if ($TargetGroupId) {
        @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $TargetGroupId }
    } else {
        @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" }
    }
    if ($FilterId) {
        $target.deviceAndAppManagementAssignmentFilterId = $FilterId
        $target.deviceAndAppManagementAssignmentFilterType = if ($FilterType) { $FilterType } else { 'include' }
    }

    $assignment = @{
        "@odata.type" = "#microsoft.graph.mobileAppAssignment"
        intent        = $Intent
        target        = $target
    }

    # settings e' specifico del tipo di app (win32LobAppAssignmentSettings per Win32, l'unico
    # tipo che questo modulo crea via New-M365OpsWin32App) - costruito SOLO se l'operatore ha
    # davvero chiesto almeno un parametro avanzato, cosi' il default resta "nessun settings"
    # (comportamento Intune implicito) quando non richiesto, invariato rispetto a prima.
    $hasRestartSettings = $RestartGracePeriodMinutes -or $RestartCountdownDisplayMinutes -or $RestartSnoozeDurationMinutes
    $hasInstallTimeSettings = $AvailableDateTime -or $DeadlineDateTime
    if ($NotificationMode -or $hasRestartSettings -or $hasInstallTimeSettings -or $DeliveryOptimizationPriority) {
        $settings = @{ "@odata.type" = "#microsoft.graph.win32LobAppAssignmentSettings" }
        if ($NotificationMode) { $settings.notifications = $NotificationMode }
        if ($DeliveryOptimizationPriority) { $settings.deliveryOptimizationPriority = $DeliveryOptimizationPriority }
        if ($hasRestartSettings) {
            $settings.restartSettings = @{
                "@odata.type" = "microsoft.graph.win32LobAppRestartSettings"
                gracePeriodInMinutes = $RestartGracePeriodMinutes
                countdownDisplayBeforeRestartInMinutes = $RestartCountdownDisplayMinutes
                restartNotificationSnoozeDurationInMinutes = $RestartSnoozeDurationMinutes
            }
        }
        if ($hasInstallTimeSettings) {
            $settings.installTimeSettings = @{
                "@odata.type" = "microsoft.graph.mobileAppInstallTimeSettings"
                useLocalTime = $UseLocalTime
            }
            if ($AvailableDateTime) { $settings.installTimeSettings.startDateTime = $AvailableDateTime }
            if ($DeadlineDateTime) { $settings.installTimeSettings.deadlineDateTime = $DeadlineDateTime }
        }
        $assignment.settings = $settings
    }

    $body = @{ mobileAppAssignments = @($assignment) }

    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceAppManagement/mobileApps/$AppId/assign" -Body $body -Beta | Out-Null
    $scope = if ($TargetGroupId) { "gruppo $TargetGroupId" } else { "All Devices" }
    $filterNote = if ($FilterId) { ", filtro $FilterId ($($target.deviceAndAppManagementAssignmentFilterType))" } else { "" }
    Write-Host "Assegnata come '$Intent' a $scope$filterNote." -ForegroundColor Green
}
