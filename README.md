# RoboEdu

## Come funziona?

Le registrazioni partono dallo script `roboEdu.sh`, che recupera gli orari
delle lezioni dall'endpoint pubblico di [unibo.it](https://unibo.it) e assegna
ad ogni lezione selezionata un sottoprocesso, che aspetta l'inizio della
lezione, fa partire la registrazione e la ferma. Quando mancano 10 minuti
dall'inizio della lezione, viene affittato un server sul cloud di Hetzner
attraverso Terraform, utilizzando la chiave fornita in `secrets/hcloud_key`.
Con ansible viene preparato il server, installando pacchetti e trasferendo gli
script necessari, dopodiché viene fatta partire la registrazione vera e
propria.\
Per unirsi alla lezione viene automatizzato il browser Chromium
con Puppeteer, utilizzando le credenziali fornite in `secrets/unibo_login.yml`
per accedere.\
Vengono catturati degli screenshot ogni minuto per controllare
che la registrazione prosegua correttamente e vengono trasferiti in
`screencaps/`.\
Le registrazioni vengono codificate con H.265 per ottimizzare lo
spazio occupato, questo significa che sarà necessario utilizzare dei media
player che supportano questo formato, come [VLC](https://www.videolan.org/vlc/)
o [MPV](https://github.com/mpv-player/mpv).\
Una volta terminata la lezione, dopo 10 minuti viene scaricata la registrazione
nella cartella `regs/`.

## Dipendenze
- OpenSSH
- curl
- jq
- terraform
- ansible >= 2.8.0 (versioni precedenti potrebbero non riconoscere
correttamente la versione di Python usata)

## Come far partire le registrazioni
- crea `secrets/unibo_login.yml` con variabili `username`, `password`, ad
esempio:
```yaml
username: "nome.cognome@studio.unibo.it"
password: "la_mia_password"
```
- crea `secrets/hcloud_key` contenente **solo** il token per le API di Hetzner
- lancia lo script con `./roboEdu.sh <nome_corso> <anno>`, oppure lancia
`./roboEdu.sh -h` per ottenere le opzioni disponibili

## Come automatizzare le registrazioni

Per rendere tutto questo automatico è consigliato preparare un cron job che
lancia lo script ogni giorno prima dell'inizio della prima lezione. Un esempio
potrebbe essere il seguente:
```sh
#!/bin/bash
mkdir -p /var/log/roboEdu/
/path/to/roboEdu.sh <nomecorso> <anno> >> /var/log/roboEdu/<nomecorso>-<anno>-$(date '+%y%m%d').log 2>&1
```


