#*********************************************************************************************************************
#Run remote commands on Leafs/Spines from apic. Supports commands from ibash, vsh, vsh_lc, root, any available shells
#
#*Note, to remotely call a script that is configured on the leaf or spine specify the full path of the script.
#
#Enter the node id's separated by spaces after the script path to execute. Ex:
#/tmp/remoteShellCmds.sh 101 102 103
#
#To get full list of all nodes in the fabric run:
#acidiag fnvread | egrep " active" | egrep "leaf|spine" | awk '{print $1}' |  sed -e 'H;${x;s/\n/ /g;s/^\s//;p;};d'
#*********************************************************************************************************************
#!/bin/bash

function log() {
    ts=`date '+%Y-%m-%dT%H:%M:%S'`
    echo "$ts $1"
}

rm -rf /data/techsupport/remoteCommands
rm -f ~/.ssh/known_hosts
mkdir /data/techsupport/remoteCommands
DIR="/data/techsupport/remoteCommands"

string="$@"
if [[ $string == *,* ]]; then
  echo "Please use spaces to separate nodeId's. Exiting..."
  exit 1
fi

read -p "Enter Your username: "  username
#echo "Welcome $username"
read -s -p "Enter Password: " pswd
echo -e "\n"
read -p "Enter 0 to use OOB or 1 to use infra connectivity: " conn
echo -e "\n"
read -p "Enter Commands to run. Press enter after each or paste in many with each on new line. Type quit when done. 
"  'CMD'

while [ "$CMD" != "quit" ]
do
   CMD2="$CMD2 ; $CMD"
   read -p ""  'CMD'
done
CMD2=`echo "$CMD2" | sed -r 's/^\s+;\s//g'`
echo Commands to run: "$CMD2"

########Infra Connectivity########
if [[ $conn == "1" ]]; then
    log "Using INFRA connectivity..."
    myAddr=`moquery -c topSystem -f "top.System.name==\"\`echo $HOSTNAME\`\"" | egrep "^address\s+" | awk '{print $3}'`
    for nodeId in "$@"
        do
        nodeAddr=`moquery -c topSystem -f 'top.System.id=="'$nodeId'"' | egrep "address" | awk '{print $3}'`
        log "Connecting to node $nodeId at $nodeAddr"
            if [[ $nodeAddr != "" ]]; then
                log "Commands run: $CMD2" >> $DIR/node-$nodeId.txt
                sshpass -p "$pswd" ssh -f -o ServerAliveInterval=2 -o ServerAliveCountMax=1 -o ConnectTimeout=2 -tq $username@$nodeAddr -b $myAddr "$CMD2" 1>>$DIR/node-$nodeId.txt 2>>$DIR/node-"$nodeId"Err.txt
                    if [ "$?" != 0 ] ; then
                        log "Failed to connect to $nodeId"
                    fi
            else
                log "Non-existent node-id, skipping $nodeId"
            fi
        done
fi

########OOB Connectivity########
if [[ $conn == "0" ]]; then
    log "Using Out-of-Band connectivity..."
    myAddr=`moquery -c topSystem -f "top.System.name==\"\`echo $HOSTNAME\`\"" | egrep "oobMgmtAddr\s" | awk '{print $3}'`
    for nodeId in "$@"
        do
        nodeAddr=`moquery -c topSystem -f 'top.System.id=="'$nodeId'"' | egrep "oobMgmtAddr\s" | awk '{print $3}'`
        log "Connecting to node $nodeId at $nodeAddr"
        if [[ $nodeAddr != "" ]]; then
            log "Commands run: $CMD2" >> $DIR/node-$nodeId.txt
            sshpass -p "$pswd" ssh -f -o ServerAliveInterval=2 -o ServerAliveCountMax=1 -o ConnectTimeout=2 -tq $username@$nodeAddr -b $myAddr "$CMD2" 1>>$DIR/node-$nodeId.txt 2>>$DIR/node-"$nodeId"Err.txt
                if [ "$?" != 0 ] ; then
                    log "Failed to connect to $nodeId"
                fi
        else
            log "Non-existent node-id, skipping $nodeId"
        fi
        done
fi
    
log "Command outputs are at /data/techsupport/remoteCommands"
log "Invalid commands are at /data/techsupport/remoteCommands/node-<id>Err.txt"
