# ard-plus-dl
Skript zum herunterladen von Videos von ARD Plus

![Bildschirmfoto 2023-12-29 um 17 25 27](https://user-images.githubusercontent.com/9810829/293396091-2b2a6fc9-91ab-43f6-81c4-670bcd4762f1.png)
## Anforderungen

- Shell/Bash (z.B. macOS Terminal)
- [jq](https://jqlang.github.io/jq/)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- Gnu-Tools: curl, grep, awk, echo, cut, sed, base64
- ARD Plus [Mitgliedschaft](https://www.ardplus.de/) (14 Tage kostenlos)

## Benutzung
Skript [downloaden](https://gist.githubusercontent.com/marco79cgn/b09e26beaaf466cb04f9d74122866048/raw/e6b7e821084b0b52406e6cb675821a3ee2794916/ard-plus-dl.sh) und ausführbar machen: `chmod 755 ard-plus-dl.sh`

Anschließend das Skript aufrufen und drei Parameter mitgeben:
`./ard-plus-dl.sh <url> <username> <password>` 

Die URL ist die Übersichtsseite eines Films oder einer Serie bei ARD Plus, zum Beispiel 
Gegen den Wind (Serie):
`https://www.ardplus.de/details/a0T0100000064DB-gegen-den-wind`
Lola rennt (Film): 
`https://www.ardplus.de/details/a0S01000000EWYi-lola-rennt`

Das Skript erkennt automatisch, ob es sich um einen Film oder eine Serie handelt. Filme werden unmittelbar geladen. Im Falle einer Serie werden alle gefundenen Staffeln aufgelistet und zur Auswahl angeboten. 

Filme und Serien werden automatisch mit mehreren Tonspuren geladen (z.B. deutsch & englisch), sofern verfügbar. Auch die Untertitel werden berücksichtigt.

Es können zusätzlich zu Filmen und Serien auch ganze Tatort Ausgaben pro Stadt geladen werden, z.B. alle Folgen aus Bremen mit der URL:
`https://www.ardplus.de/kategorie/tatort-bremen`

Die Zieldateien werden sinnvoll benannt, z.B.: 
`S01E01 - Schönes Wochenende.mp4`
oder 
`Lola rennt (1998).mp4`

## Alternative: Docker
Ein fertiges Docker Image kann über das vorhandene Dockerfile gebaut und benutzt werden. 

Beispiel
