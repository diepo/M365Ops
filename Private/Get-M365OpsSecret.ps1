function Get-M365OpsSecret {
    <#
    .SYNOPSIS
        Legge il valore di una variabile d'ambiente per nome, con fallback al registro
        (HKCU:\Environment) per il caso 'setx appena eseguito, processo non ancora riavviato'.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name
    )

    $value = [System.Environment]::GetEnvironmentVariable($Name, 'Process')
    if ($value) { return $value }

    $value = [System.Environment]::GetEnvironmentVariable($Name, 'User')
    if ($value) { return $value }

    try {
        $regValue = (Get-ItemProperty -Path "HKCU:\Environment" -Name $Name -ErrorAction Stop).$Name
        if ($regValue) { return $regValue }
    }
    catch {}

    return $null
}
