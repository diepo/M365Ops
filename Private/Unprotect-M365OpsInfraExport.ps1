function Unprotect-M365OpsInfraExport {
    <#
    .SYNOPSIS
        Decifra un pacchetto prodotto da Protect-M365OpsInfraExport, data la passphrase usata in
        esportazione. Verifica SEMPRE l'HMAC PRIMA di tentare la decifratura (verifica-poi-
        decifra, mai il contrario: decifrare per primo esporrebbe a un padding-oracle se la
        passphrase o i dati fossero sbagliati/manomessi) - lancia un errore generico identico su
        qualunque fallimento (passphrase errata O dati corrotti), senza distinguere i due casi,
        cosi' non si da' a chi tenta un attacco nessun segnale su quale parte del pacchetto sia
        sbagliata.
    .PARAMETER Envelope
        L'oggetto { kdf; iterations; salt; iv; hmac; ciphertext } prodotto da
        Protect-M365OpsInfraExport (deserializzato dal JSON del file importato).
    .PARAMETER Passphrase
        Passphrase in chiaro inserita dall'utente al momento dell'import.
    .OUTPUTS
        L'oggetto originale (deserializzato dal JSON decifrato).
    #>
    param(
        [Parameter(Mandatory)] $Envelope,
        [Parameter(Mandatory)] [string]$Passphrase
    )

    $salt = [Convert]::FromBase64String($Envelope.salt)
    $iv = [Convert]::FromBase64String($Envelope.iv)
    $cipherBytes = [Convert]::FromBase64String($Envelope.ciphertext)
    $expectedTag = [Convert]::FromBase64String($Envelope.hmac)

    # Tetto sul numero di iterazioni PBKDF2 letto dall'envelope (26/08/2026, bug reale trovato
    # durante la review sicurezza: un envelope malevolo/corrotto con un valore assurdo qui, es.
    # 2 miliardi, mandava Rfc2898DeriveBytes a macinare per un tempo indefinito - confermato dal
    # vivo che questo blocca l'INTERO processo Server.ps1, single-threaded, negando il servizio a
    # QUALUNQUE richiesta successiva finche' il calcolo non termina da solo, anche a
    # /api/restart stesso, servito dallo stesso processo bloccato - richiesto un kill manuale del
    # processo per riprendersi). Un valore mancante resta sul default 100.000 (retrocompatibile
    # con un envelope che non porta questo campo); un valore presente ma fuori da un intervallo
    # ragionevole (1..2.000.000, ~20x il default, abbondante per un eventuale rialzo futuro dello
    # standard) viene trattato come QUALUNQUE altra manomissione del pacchetto - stesso errore
    # generico usato per l'HMAC che non torna, mai un dettaglio su quale campo specifico non va -
    # rifiutato PRIMA di qualunque lavoro costoso, non dopo.
    $iterations = 100000
    if ($Envelope.iterations) {
        $parsedIterations = 0
        $iterationsOk = [int]::TryParse([string]$Envelope.iterations, [ref]$parsedIterations)
        if (-not $iterationsOk -or $parsedIterations -lt 1 -or $parsedIterations -gt 2000000) {
            throw "Passphrase errata o file di export danneggiato/manomesso."
        }
        $iterations = $parsedIterations
    }

    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Passphrase, $salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $keyMaterial = $kdf.GetBytes(64)
    $aesKey = $keyMaterial[0..31]
    $hmacKey = $keyMaterial[32..63]

    $toAuth = New-Object byte[] ($iv.Length + $cipherBytes.Length)
    [Array]::Copy($iv, 0, $toAuth, 0, $iv.Length)
    [Array]::Copy($cipherBytes, 0, $toAuth, $iv.Length, $cipherBytes.Length)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256(, $hmacKey)
    $actualTag = $null
    try { $actualTag = $hmac.ComputeHash($toAuth) } finally { $hmac.Dispose() }

    # Confronto a tempo costante scritto a mano (invece di System.Security.Cryptography.
    # CryptographicOperations.FixedTimeEquals, disponibile solo da .NET Core 2.1+ - non su .NET
    # Framework/Windows PowerShell 5.1, che questo modulo dichiara di supportare) - itera sempre
    # l'intera lunghezza a prescindere da DOVE cade la prima differenza, evitando un side-channel
    # a tempo che rivelerebbe quanti byte iniziali dell'HMAC sono corretti.
    $equal = $actualTag.Length -eq $expectedTag.Length
    if ($equal) {
        $diff = 0
        for ($i = 0; $i -lt $actualTag.Length; $i++) { $diff = $diff -bor ($actualTag[$i] -bxor $expectedTag[$i]) }
        $equal = $diff -eq 0
    }
    if (-not $equal) {
        throw "Passphrase errata o file di export danneggiato/manomesso."
    }

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $aesKey
    $aes.IV = $iv
    $plainBytes = $null
    try {
        $decryptor = $aes.CreateDecryptor()
        $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
    }
    catch {
        throw "Passphrase errata o file di export danneggiato/manomesso."
    }
    finally {
        $aes.Dispose()
    }

    $json = [System.Text.Encoding]::UTF8.GetString($plainBytes)
    ConvertFrom-Json -InputObject $json
}
