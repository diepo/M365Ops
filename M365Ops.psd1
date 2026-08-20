@{
    RootModule        = 'M365Ops.psm1'
    ModuleVersion     = '0.9.14'
    GUID              = 'a3f1c2e0-4b8a-4e6f-9c1d-8e2f6a7b5c3d'
    Author            = 'diego'
    Description       = 'Automazione M365 Modern Workplace (Intune/Entra) con motore di ragionamento AI pluggable. Multi-tenant via profili in Config\tenants.json.'
    PowerShellVersion = '5.1'
    # '*' invece di un elenco esplicito: la lista reale e' costruita dinamicamente in
    # M365Ops.psm1 (tutto Public\ + gli script validi in Scripts\Custom\) - un nuovo
    # cmdlet o script personalizzato diventa disponibile senza piu' dover sincronizzare
    # manualmente questo file (fonte di errori quando le cmdlet erano 80+).
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
