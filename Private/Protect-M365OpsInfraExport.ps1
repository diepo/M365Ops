function Protect-M365OpsInfraExport {
    <#
    .SYNOPSIS
        Cifra un payload (il diagramma di infrastruttura) con una passphrase, per l'esportazione
        verso un altro PC/installazione (25/08/2026, richiesto esplicitamente dall'utente: poter
        condividere un diagramma tra installazioni diverse dell'app, con l'export cifrato "se
        possibile"). AES-256-CBC + HMAC-SHA256 (cifra-poi-autentica), non AES-GCM: AES-GCM non e'
        disponibile in modo affidabile su Windows PowerShell 5.1/.NET Framework (la classe
        System.Security.Cryptography.AesGcm esiste solo da .NET Core 3+), mentre CBC+HMAC
        funziona identico sia li' sia sotto PowerShell 7 (il runtime reale della GUI).
    .PARAMETER Payload
        L'oggetto da cifrare (serializzato in JSON prima della cifratura).
    .PARAMETER Passphrase
        Passphrase in chiaro scelta dall'utente al momento dell'export - MAI salvata da nessuna
        parte, esiste solo per la durata di questa chiamata.
    .OUTPUTS
        pscustomobject { kdf; iterations; salt; iv; hmac; ciphertext } - tutti i campi binari in
        base64, pronti per ConvertTo-Json.
    .NOTES
        Derivazione chiave: PBKDF2 (Rfc2898DeriveBytes, 100.000 iterazioni, salt casuale a 16
        byte) - 64 byte di materiale derivato, i primi 32 per la chiave AES, i successivi 32 per
        la chiave HMAC (due chiavi separate, mai la stessa chiave riusata per cifratura e
        autenticazione - errore classico da evitare). L'HMAC copre IV+ciphertext insieme, non
        solo il ciphertext, cosi' un IV scambiato con quello di un altro export fa fallire
        comunque la verifica in decifratura.
    #>
    param(
        [Parameter(Mandatory)] $Payload,
        [Parameter(Mandatory)] [string]$Passphrase
    )

    $json = ConvertTo-Json -InputObject $Payload -Depth 10 -Compress
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    $salt = New-Object byte[] 16
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
    $iterations = 100000
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Passphrase, $salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $keyMaterial = $kdf.GetBytes(64)
    $aesKey = $keyMaterial[0..31]
    $hmacKey = $keyMaterial[32..63]

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $aesKey
    $aes.GenerateIV()
    $iv = $aes.IV
    $cipherBytes = $null
    try {
        $encryptor = $aes.CreateEncryptor()
        $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    }
    finally {
        $aes.Dispose()
    }

    $toAuth = New-Object byte[] ($iv.Length + $cipherBytes.Length)
    [Array]::Copy($iv, 0, $toAuth, 0, $iv.Length)
    [Array]::Copy($cipherBytes, 0, $toAuth, $iv.Length, $cipherBytes.Length)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256(, $hmacKey)
    $tag = $null
    try { $tag = $hmac.ComputeHash($toAuth) } finally { $hmac.Dispose() }

    [pscustomobject]@{
        kdf        = 'PBKDF2-SHA256'
        iterations = $iterations
        salt       = [Convert]::ToBase64String($salt)
        iv         = [Convert]::ToBase64String($iv)
        hmac       = [Convert]::ToBase64String($tag)
        ciphertext = [Convert]::ToBase64String($cipherBytes)
    }
}
