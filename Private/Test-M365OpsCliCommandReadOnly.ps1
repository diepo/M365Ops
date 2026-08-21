function Test-M365OpsCliCommandReadOnly {
    <#
    .SYNOPSIS
        Classifica un comando CLI Microsoft 365 (npm @pnp/cli-microsoft365) come sola
        lettura o scrittura, SENZA mantenere una lista di ~400 comandi a mano (26/08/2026).

        I comandi di questa CLI seguono una convenzione di naming molto regolare - "<gruppo>
        [sottogruppo] <verbo>" (es. "spo site get", "teams meeting list", "entra user add",
        "outlook mail send") - verificato sulla documentazione ufficiale
        (pnp.github.io/cli-microsoft365) su un campione ampio di comandi in gruppi diversi
        (spo/entra/outlook/teams/planner), mai un'eccezione trovata alla posizione del verbo
        (sempre l'ULTIMA parola prima di eventuali flag). Classifica come lettura SOLO i
        verbi noti in $readVerbs; QUALUNQUE altro verbo, incluso uno non ancora visto, e'
        trattato come scrittura per difetto - mai il contrario: un falso negativo (un comando
        di lettura trattato come scrittura) costa solo una conferma in piu' all'utente, un
        falso positivo (un comando di scrittura eseguito senza conferma) sarebbe una
        violazione diretta del principio "mai una scrittura senza conferma esplicita" gia' in
        vigore per ogni altro strumento di questo modulo.
    .PARAMETER Command
        Il comando completo SENZA il prefisso "m365 ", es. "spo site get --url ...".
    .OUTPUTS
        $true se il verbo finale e' un verbo di lettura noto, $false altrimenti.
    #>
    param([Parameter(Mandatory)] [string]$Command)

    $readVerbs = @('get', 'list', 'search', 'export', 'status')

    # Il verbo e' l'ULTIMA parola PRIMA del primo flag (es. "spo site get --url https://...":
    # il verbo e' "get", non "https://..." - un valore di flag non inizia per "-" quanto un
    # flag stesso, quindi va escluso per POSIZIONE (tutto cio' che segue il primo flag),
    # non solo filtrando le parole che iniziano per "-" (bug reale trovato in revisione prima
    # del primo uso: quel filtro da solo avrebbe lasciato passare i VALORI dei flag,
    # producendo un "verbo" quasi sempre sbagliato su qualunque comando con parametri).
    $words = @($Command -split '\s+' | Where-Object { $_ })
    $pathWordCount = $words.Count
    for ($i = 0; $i -lt $words.Count; $i++) {
        if ($words[$i].StartsWith('-')) { $pathWordCount = $i; break }
    }
    if ($pathWordCount -eq 0) { return $false }

    $verb = $words[$pathWordCount - 1].ToLowerInvariant()
    return $verb -in $readVerbs
}
