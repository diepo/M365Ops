function New-M365OpsSelfSignedCertificate {
    <#
    .SYNOPSIS
        Genera un nuovo certificato autofirmato in locale (Cert:\CurrentUser\My) per
        l'autenticazione app-only Microsoft Entra ID, e aggiorna il profilo tenant ATTIVO col
        thumbprint risultante - stessi identici parametri gia' documentati in guida (sezione
        5.1, "una tantum sul PC amministrativo"), qui automatizzati dietro un pulsante invece
        di copiare/incollare i comandi a mano.

        LA CHIAVE PRIVATA RESTA SEMPRE SU QUESTO PC: restituisce solo il contenuto PUBBLICO
        (.cer, nessun segreto) per il download - da caricare manualmente su Entra ID
        (Certificati e segreti). Resta l'UNICO passaggio manuale, per scelta (27/08/2026,
        richiesto esplicitamente dall'utente, opzione scelta tra due proposte): un upload
        automatico via Graph richiederebbe il permesso Application.ReadWrite.All, non concesso
        in nessun profilo di questo progetto e contro la disciplina di minimo privilegio
        seguita finora - un passaggio manuale in piu' e' preferibile a un permesso cosi'
        potente per un'operazione una tantum.
    .PARAMETER SubjectName
        Nome soggetto (CN) del certificato. Se omesso, usa "M365Ops-<nome profilo attivo>".
    #>
    param([string]$SubjectName)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name
    if (-not $SubjectName) { $SubjectName = "M365Ops-$tenantName" }

    # Stessi identici parametri della sezione 5.1 della guida (verificati e in uso da mesi in
    # questo progetto per il certificato Exchange) - nessun parametro nuovo indovinato qui.
    $cert = New-SelfSignedCertificate -Subject "CN=$SubjectName" `
        -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable `
        -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256

    $publicBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $publicBase64 = [Convert]::ToBase64String($publicBytes)

    # Aggiorna il profilo tenant ATTIVO col nuovo thumbprint. Set-M365OpsTenant sostituisce
    # l'INTERO profilo (non fa un patch parziale) - vanno ripassati esplicitamente tutti i
    # campi gia' noti (letti da Get-M365OpsActiveTenantInfo), altrimenti verrebbero azzerati
    # per sbaglio - stesso principio "mai una sostituzione silenziosa" gia' seguito ovunque nel
    # progetto per i campi di un profilo tenant.
    $info = Get-M365OpsActiveTenantInfo
    Set-M365OpsTenant -Name $tenantName -TenantId $info.TenantId -ClientId $info.ClientId `
        -SecretEnvVar $info.SecretEnvVar -AuthMode $info.AuthMode -DelegatedUpn $info.DelegatedUpn `
        -ExchangeCertThumbprint $cert.Thumbprint -EmailSender $info.EmailSender `
        -SharePointInteractiveClientId $info.SharePointInteractiveClientId

    # Set-M365OpsTenant scrive solo su disco (Config\tenants.json), non tocca il contesto gia'
    # in memoria di QUESTO processo - senza questo, il resto della sessione corrente (Connect-
    # M365OpsCliMicrosoft365, Get-M365OpsToken, ecc.) continuerebbe a vedere il thumbprint
    # vecchio (o nessuno) finche' non si cambia/riattiva il tenant.
    $script:M365OpsContext.ExchangeCertThumbprint = $cert.Thumbprint

    [pscustomobject]@{
        Thumbprint       = $cert.Thumbprint
        Subject          = $SubjectName
        NotAfter         = $cert.NotAfter
        PublicCertBase64 = $publicBase64
    }
}
