function New-M365OpsCertificateAssertion {
    <#
    .SYNOPSIS
        Costruisce il JWT "client assertion" (RFC 7523) firmato con un certificato per
        l'autenticazione app-only Microsoft Entra ID SENZA client secret - alternativa a
        Get-M365OpsToken quando il profilo tenant ha un ExchangeCertThumbprint ma nessun
        secret disponibile (21/08/2026, richiesto esplicitamente dall'utente: "possiamo
        usare il certificato anziche' il secret?" - stesso certificato gia' richiesto per
        Connect-ExchangeOnline -CertificateThumbprint, un solo materiale segreto da
        gestire invece di due).
    .NOTES
        Cerca il certificato in Cert:\CurrentUser\My prima, poi Cert:\LocalMachine\My -
        stessi due store che Connect-ExchangeOnline -CertificateThumbprint prova, cosi'
        un certificato gia' funzionante per Exchange funziona automaticamente anche qui
        senza bisogno di installarlo una seconda volta altrove.
    #>
    param(
        [Parameter(Mandatory)] [string]$Thumbprint,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$TokenEndpoint
    )

    $cert = Get-Item "Cert:\CurrentUser\My\$Thumbprint" -ErrorAction SilentlyContinue
    if (-not $cert) { $cert = Get-Item "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue }
    if (-not $cert) {
        throw "Certificato con thumbprint '$Thumbprint' non trovato ne' in Cert:\CurrentUser\My ne' in Cert:\LocalMachine\My - stesso certificato gia' usato per Exchange deve essere installato su questo PC."
    }
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    if (-not $rsa) {
        throw "Il certificato con thumbprint '$Thumbprint' non ha una chiave privata RSA accessibile su questo PC (richiesta per firmare la richiesta di token)."
    }

    function ConvertTo-M365OpsBase64Url {
        param([byte[]]$Bytes)
        [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }

    # x5t: hash SHA-1 del certificato (== il "thumbprint" stesso), non SHA-256 - richiesto
    # cosi' dalla specifica del client assertion di Microsoft Entra ID.
    $x5t = ConvertTo-M365OpsBase64Url -Bytes $cert.GetCertHash()
    $header = [ordered]@{ alg = 'RS256'; typ = 'JWT'; x5t = $x5t } | ConvertTo-Json -Compress
    $now = [DateTimeOffset]::UtcNow
    $payload = [ordered]@{
        aud = $TokenEndpoint
        iss = $ClientId
        sub = $ClientId
        jti = [guid]::NewGuid().ToString()
        nbf = $now.ToUnixTimeSeconds()
        exp = $now.AddMinutes(5).ToUnixTimeSeconds()
    } | ConvertTo-Json -Compress

    $headerB64 = ConvertTo-M365OpsBase64Url -Bytes ([Text.Encoding]::UTF8.GetBytes($header))
    $payloadB64 = ConvertTo-M365OpsBase64Url -Bytes ([Text.Encoding]::UTF8.GetBytes($payload))
    $signingInput = "$headerB64.$payloadB64"

    $signature = $rsa.SignData(
        [Text.Encoding]::UTF8.GetBytes($signingInput),
        [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $signatureB64 = ConvertTo-M365OpsBase64Url -Bytes $signature

    return "$signingInput.$signatureB64"
}
