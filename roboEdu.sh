#!/bin/sh

get_pidfile(){
    echo $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$TIPO_CORSO-$counter.pid
}

retrieve_ip() {
	jq -r ".resources[] | select(.name == \"myVps\") | .instances[].attributes.ipv4_address" $TFSTATE
}

make_inventory() {
	printf '%s ansible_user=root ansible_ssh_private_key_file="%s"\n' `retrieve_ip` $PRIV_KEY > $INVENTORY
	logd inventory creato
}

logd() {
	TIMESTAMP=$(date -Iseconds)
	echo $TIMESTAMP - $@
}

die() {
	logd FATAL ERROR - $@
	exit
}

wait_machines() {
	ip=$(retrieve_ip)
	logd "aspetto l'ip $ip"
	# Reset the saved keys
	set +e
	ssh-keygen -R "$ip" 1>/dev/null 2>/dev/null
	set -e
	echo -n "waiting"
	for WAITED_SECONDS in $(seq 0  120); do
		if ssh -q -n -i "$PRIV_KEY" \
				-o PasswordAuthentication=no \
				-o StrictHostKeyChecking=no "root@$ip" 'true'; then
			echo -e '\n\n'
			logd "Success! $ip is ready."
			break
		else
			echo -n "."
			sleep 1
		fi
	done
	echo ""
	sleep 10
}


screenshot() {
	counter=$1
	id=$2
	end=$3
	tempo=$(printf '(%s - 300)  - %s\n' `date -d $end '+%s'` `date '+%s'` | bc) # no screenshots in the last 15 minutes
	while test $tempo -gt 0; do
		ssh -i $PRIV_KEY -o StrictHostKeyChecking=no root@`retrieve_ip` 'DISPLAY=:99 import -window root /root/yolo.png'
		scp -i $PRIV_KEY -o StrictHostKeyChecking=no root@`retrieve_ip`:/root/yolo.png "$ROOT/screencaps/$NOME_CORSO-$ANNO-$id-$counter.png"
		sleep 60
		tempo=$(printf '(%s - 300)  - %s\n' `date -d $end '+%s'` `date '+%s'` | bc) 
	done
	rm "$ROOT/screencaps/$NOME_CORSO-$ANNO-$id-$counter.png"
}

record_start() {
	link=$1
	id=$2
	counter=$3

	# create private key
	set +e
	echo 'n' | ssh-keygen -N "" -q -f $PRIV_KEY
	set -e
	
    # create server with terraform
	cd $ROOT/terraform
	terraform init
	terraform apply -var="anno=$ANNO" -var="corso=$NOME_CORSO" -var="id=$id" -var="counter=$counter" -state $TFSTATE -auto-approve
	cd $ROOT
	
	make_inventory
	wait_machines

	ssh-keygen -R `retrieve_ip`
	ansible-playbook -i $INVENTORY ${ROOT}/ansible/playbook.yml --extra-vars "link=$link pupscript=$PUPSCRIPT"
}

record_stop() {
	counter=$1
	id=$2
	
	ssh -i $PRIV_KEY root@`retrieve_ip` 'killall -INT ffmpeg'
	sleep 10s #in case ffmpeg needed this
	logd Lezione finita, inizio a scaricarla
	scp -i $PRIV_KEY -o StrictHostKeyChecking=no root@`retrieve_ip`:/home/yolo/reg.mkv "$ROOT/regs/$NOME_CORSO-$ANNO-${id}_$(date '+%y%m%d')_$counter.mkv"
	logd Lezione scaricata 
	cd $ROOT/terraform
	terraform destroy -var="anno=$ANNO" -var="corso=$NOME_CORSO" -var="id=$id" -var="counter=$counter" -state $TFSTATE -auto-approve
	cd $ROOT
}

wait_and_record() {
	#parse string
	counter=$(echo $1 | sed 's/_\(.*\)_/\1/'); shift
	start=$(echo $1 | sed 's/_\(.*\)_/\1/'); shift
	end=$(echo $1 | sed 's/_\(.*\)_/\1/'); shift
	teams=$(echo $1 | sed 's/_\(.*\)_/\1/'); shift
	id=$(echo $1 | sed 's/_\(.*\)_/\1/' | tr '_' '-'); shift
	note=$(echo $1 | sed 's/_\(.*\)_/\1/'); shift
	nome=$(echo $@ | sed 's/_\(.*\)_/\1/'); shift
	
	if test -z "$counter" \
		|| test -z "$start" \
		|| test -z "$end" \
		|| test -z "$teams" \
		|| test -z "$id" \
		|| test -z "$nome"; then
			die "queste variabili non possono essere vuote: \$counter \$end \$teams \$id \$nome: $counter $end $teams $id $nome"
	fi

	if test -n "$FILTER_CORSO" && ! (echo "$FILTER_CORSO_STRING" | grep $id > /dev/null); then
		logd skipped corso $id - corso not in $FILTER_CORSO_STRING
		exit
	fi
	if test -n "$FILTER_NOTE" -a $note = "${FILTER_NOTE_STRING}"; then
		logd skipped note $FILTER_NOTE_STRING
		exit
	fi

	# make variables
	PRIV_KEY=${ROOT}/secrets/ssh/$NOME_CORSO-$ANNO-$id-$counter-key
	NOME_MACCHINA=$NOME_CORSO-$ANNO-$id-$counter-client
	INVENTORY="${ROOT}/ansible/inventory/$NOME_CORSO-$ANNO-$id-$counter.ini"
	TFSTATE="${ROOT}/terraform/states/$NOME_CORSO-$ANNO-$id-$counter.tfstate"
	export ANSIBLE_HOST_KEY_CHECKING="False"
		
	seconds_till_start=$(printf '%s - (%s + 600)\n' `date -d $start '+%s'` `date '+%s'` | bc)
	link_goodpart=$(echo $teams | grep -oE 'meetup-join[^*]+')
	link="https://teams.microsoft.com/_\#/l/${link_goodpart}"
	seconds_till_end=$(printf '(%s + 600)  - %s\n' `date -d $end '+%s'` `date '+%s'` | bc)

	if test $seconds_till_end -lt 0; then
		logd skipping $nome - alredy ended
		exit
	fi
	
	logd waiting for $seconds_till_start secondi
	logd per lezione: $nome - $id
	test $seconds_till_start -gt 0 && sleep $seconds_till_start
	record_start $link $id $counter


	seconds_till_end=$(printf '(%s + 600)  - %s\n' `date -d $end '+%s'` `date '+%s'` | bc)
	logd waiting for $seconds_till_end secondi
	logd per lezione: $nome - $id

	screenshot $counter $id $end &
	sleep $seconds_till_end
	record_stop $counter $id

	logd tutto finito
	
	# remove created files:
	rm $PRIV_KEY $INVENTORY $TFSTATE
}

destroy_all() {
	set +e
	# get piano for today
	oggi=$(date '+%Y-%m-%d')
	counter=0
	kill -TERM -$(cat $PIDFILE)
	rm $PIDFILE
	curl -s "https://corsi.unibo.it/laurea/$NOME_CORSO/orario-lezioni/@@orario_reale_json?anno=$ANNO&curricula=&start=$oggi&end=$oggi" | jq -r '.[] | .cod_modulo' |\
		while read line; do
			counter=$(($counter + 1))
			id=$line
			# destroy terraform stuff
			TFSTATE="${ROOT}/terraform/states/$NOME_CORSO-$ANNO-$id.tfstate"
			cd $ROOT/terraform
			terraform destroy -var="anno=$ANNO" -var="corso=$NOME_CORSO" -var="id=$id" -var="counter=$counter" -state $TFSTATE -auto-approve
			cd $ROOT
			# remove files
			PRIV_KEY=${ROOT}/secrets/ssh/$NOME_CORSO-$ANNO-$id-$counter-key
			INVENTORY="${ROOT}/ansible/inventory/$NOME_CORSO-$ANNO-$id.ini"
			rm $PRIV_KEY $INVENTORY
			rm $ROOT/logs_and_pid/$NOME_CORSO-${ANNO}_${id}_$(date '+%y%m%d')_$counter.log
			rm $PIDFILE
		done 
		exit

}

show_help() {
	echo "Utilizzo: $0 [-d] <nomecorso> <anno> [id]"
	echo "-h help"
	echo "-d distruggi tutti i server esistenti"
	echo "-l localhost"
	echo "-v verboso (mantieni i log)"
	echo "-M magistrale"
    echo "-f filtro [id] // questo è un filtro positivo, registrerà solamente le lezioni con questo id" 
    echo "-n filtro [nota] // questo è un filtro negativo, salterà le lezioni con la nota specificata" 
	echo "-m 'orarioInizio orarioFine URL ID' // registra manualmente da un meeting teams del giorno corrente"
	exit
}

manual(){
    # M substitutes counter to specify that it's a manual recording
    counter="M"
    timeStart=$1 
    timeEnd=$2
    url=$3
    ID=$4
    PIDFILE=`get_pidfile`
    echo $counter - $timeStart $timeEnd $url $ID $NOME_CORSO $ANNO
    wait_and_record $counter ${oggi}T$1 ${oggi}T$2 $3 $4 __ $NOME_CORSO $ANNO > $ROOT/logs_and_pid/$NOME_CORSO-${ANNO}_${ID}_$(date '+%y%m%d')_$counter.log 2>&1 &
    echo $! > $PIDFILE
    set +e
    wait $(cat $PIDFILE)
    set -e
    echo $NOME_CORSO-$ANNO-$counter ha finito
    test -z VERBOSE && rm $ROOT/logs_and_pid/${NOME_CORSO}-${ANNO}_*_$(date '+%y%m%d')_${counter}.log
    rm $PIDFILE
    set +e
    rm -f $ROOT/screencaps/$NOME_CORSO-$ANNO-*-$counter.png
    set -e
    rm $PIDFILE
    exit
}

############### 
# ENTRY POINT #
###############

set -e

if test $# -lt 2; then
	show_help
fi

TIPO_CORSO="laurea"

while getopts ":hdlvMm:f:n:c:" opt; do
	case $opt in
		"h") show_help; exit;;
		"d") echo "distruggi tutto" ; DESTROY=true;;
		"l") echo "localhost" ; LOCALHOST=true;;
		"v") echo "verboso" ; VERBOSE=true;;
		"M") echo "magistrale"; TIPO_CORSO="magistrale";;
		"f") echo "filtro corsi: $OPTARG"; FILTER_CORSO=true; FILTER_CORSO_STRING=$OPTARG;;
		"n") echo "filtro note: $OPTARG";FILTER_NOTE=true; FILTER_NOTE_STRING=$OPTARG;;
		"m") echo "manuale"; MANUAL=true; MANUAL_STRING=$OPTARG;; 
<<<<<<< HEAD
		"c") echo "curriculum"; CURRICULA=$OPTARG;; 
=======
		"c") echo "curricula"; CURRICULA=$OPTARG;;
>>>>>>> 81448d26c9fa8acab1c8e5f9c9ff3be41649bc50
	esac
done
shift $(($OPTIND - 1))

NOME_CORSO=$1
ANNO=$2
STARTSCRIPT=$(realpath $0)
ROOT=$(dirname $STARTSCRIPT)
PUPSCRIPT="teams"

test -n "$DESTROY" && destroy_all

# get piano for today
oggi=$(date '+%F')
counter=0

# manual recording
test -n "$MANUAL" && manual $MANUAL_STRING

echo $$ > $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$TIPO_CORSO.pid

<<<<<<< HEAD
# no process substitution in P0SIX sh
tmpdir=$(mktemp -d)
exec 3> $tmpdir/fd3

curl -s "https://corsi.unibo.it/$TIPO_CORSO/$NOME_CORSO/orario-lezioni/@@orario_reale_json?anno=$ANNO&curricula=$CURRICULA&start=$oggi&end=$oggi" | jq -r '.[] | .start + " " + .end + " " + .teams + " " + .cod_modulo + " _" + .note + "_ " + .title' > $tmpdir/fd3

while read line; do
	ID=$(echo $line | cut -d' ' -f4)
	counter=$(($counter + 1))
	wait_and_record $counter $line > $ROOT/logs_and_pid/$NOME_CORSO-${ANNO}_${ID}_$(date '+%y%m%d')_$counter.log 2>&1 &
	echo $! > $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$counter.pid
done < $tmpdir/fd3

rm -r $tmpdir
=======
curl -s "https://corsi.unibo.it/$TIPO_CORSO/$NOME_CORSO/orario-lezioni/@@orario_reale_json?anno=$ANNO&curricula=$CURRICULA&start=$oggi&end=$oggi" | jq -r '.[] | "_" + .start + "_ _" + .end + "_ _" + .teams + "_ _" + .cod_modulo + "_ _" + .note + "_ _" + .title + "_"' |
    while read line; do
        ID=$(echo $line | cut -d' ' -f4)
        counter=$(($counter + 1))
        PIDFILE=`get_pidfile`
        wait_and_record $counter $line > $ROOT/logs_and_pid/$NOME_CORSO-${ANNO}_${ID}_$(date '+%y%m%d')_$counter.log 2>&1 &
        echo $! > $PIDFILE
    done
>>>>>>> 81448d26c9fa8acab1c8e5f9c9ff3be41649bc50

while test $counter -gt 0; do
	set +e
	wait $(cat $PIDFILE)
	set -e
	echo $NOME_CORSO-$ANNO-$counter ha finito
	test -z VERBOSE && rm $ROOT/logs_and_pid/$NOME_CORSO-${ANNO}_*_$(date '+%y%m%d')_$counter.log
	rm $PIDFILE
	set +e
	rm -f $ROOT/screencaps/$NOME_CORSO-$ANNO-*-$counter.png
	set -e
	counter=$(($counter - 1))
done
rm $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$TIPO_CORSO.pid
