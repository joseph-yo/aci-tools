#!/bin/bash
#################################################################
#author josephyo
#
#This script automates running elams on modular spines from ibash
#################################################################

##################
#Define Functions#
##################
function log() {
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    echo "$ts $1"
}

function ssh_util() {
    mod=$1
    pswd="root"
    socket_file=/tmp/ssh-root@mod$mod:22
        
        if ! [ -S "$socket_file" ]; then
            options="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o controlMaster=yes -o controlPath=$socket_file -o controlPersist=yes -q"
            ssh_command="sshpass -p $pswd ssh $options root@mod$mod /lc/isan/bin/vsh_lc"
        else
            options="-S $socket_file"
            ssh_command="ssh $options root@mod$mod /lc/isan/bin/vsh_lc"
        fi
}

function get_elam_conditions() {
    #build syntax for each condition
    declare -A condition_dict
    condition_dict['outer l2 source mac']='set outer l2 src_mac'
    condition_dict['outer l2 destination mac']='set outer l2 dst_mac'
    condition_dict['outer arp source ip']='set outer arp source-ip-addr'
    condition_dict['outer arp target ip']='set outer arp target-ip-addr'
    condition_dict['outer arp source mac']='set outer arp source-mac-addr'
    condition_dict['outer arp target mac']='set outer arp target-mac-addr'
    condition_dict['outer ipv4 source ip']='set outer ipv4 src_ip'
    condition_dict['outer ipv4 destination ip']='set outer ipv4 dst_ip'
    condition_dict['outer ipv4 dscp']='set outer ipv4 dscp'
    condition_dict['outer ipv4 protocol']='set outer ipv4 next-protocol'
    condition_dict['outer l4 source port']='set outer l4 src-port'
    condition_dict['outer l4 dest port']='set outer l4 dst-port'
    condition_dict['outer l4 vnid']='set outer l4 tn-seg-id'
    condition_dict['outer l4 sclass']='set outer l4 sclass'
    condition_dict['outer l4 DL bit set']='set outer l4 nonce-dl'
    condition_dict['outer l4 src policy applied']='set outer l4 nonce-sp'
    condition_dict['outer l4 flags']='set outer l4 flags'
    condition_dict['inner l2 source mac']='set inner l2 src_mac'
    condition_dict['inner l2 destination mac']='set inner l2 dst_mac'
    condition_dict['inner arp source ip']='set inner arp source-ip-addr'
    condition_dict['inner arp target ip']='set inner arp target-ip-addr'
    condition_dict['inner arp source mac']='set inner arp source-mac-addr'
    condition_dict['inner arp target mac']='set inner arp target-mac-addr'
    condition_dict['inner ipv4 source ip']='set inner ipv4 src_ip'
    condition_dict['inner ipv4 destination ip']='set inner ipv4 dst_ip'
    condition_dict['inner ipv4 dscp']='set inner ipv4 dscp'
    condition_dict['inner ipv4 protocol']='set inner ipv4 next-protocol'
    condition_dict['inner ipv6 destination ip']='set inner ipv6 dst_ip'
    condition_dict['inner ipv6 source ip']='set inner ipv6 src_ip'
    condition_dict['inner ipv6 next-header']='set inner ipv6 next-header'
    condition_dict['inner l4 source port']='set inner l4 src-port'
    condition_dict['inner l4 dest port']='set inner l4 dst-port'
    condition_dict['inner l4 flags']='set inner l4 flags'

    #determine which in-select values match the user's input
    declare -A insel_dict
    insel_dict['outer l2 source mac             > Format : aaaa.bbbb.cccc']='6 14'
    insel_dict['outer l2 destination mac        > Format : aaaa.bbbb.cccc']='6 14'
    insel_dict['outer arp source ip             > Format : d.d.d.d']='6'
    insel_dict['outer arp target ip             > Format : d.d.d.d']='6'
    insel_dict['outer arp source mac            > Format : aaaa.bbbb.cccc']='6'
    insel_dict['outer arp target mac            > Format : aaaa.bbbb.cccc']='6'
    insel_dict['outer ipv4 source ip            > Format : d.d.d.d']='6 14'
    insel_dict['outer ipv4 destination ip       > Format : d.d.d.d']='6 14'
    insel_dict['outer ipv4 dscp                 > Format : 0-64']='6 14'
    insel_dict['outer ipv4 protocol             > Format : 0-255']='6 14'
    insel_dict['outer l4 source port            > Format : 0-65535']='6'
    insel_dict['outer l4 dest port              > Format : 0-65535']='6'
    insel_dict['outer l4 vnid                   > Format : 0x0-0xffffff']='14'
    insel_dict['outer l4 sclass                 > Format : 0-65535']='6 14'
    insel_dict['outer l4 DL bit set             > Format : 0-1']='6 14'
    insel_dict['outer l4 src policy applied     > Format : 0-1']='6 14'
    insel_dict['outer l4 flags                  > Format : 0x0-0xff']='6 14'
    insel_dict['inner l2 source mac             > Format : aaaa.bbbb.cccc']='7 14'
    insel_dict['inner l2 destination mac        > Format : aaaa.bbbb.cccc']='7 14'
    insel_dict['inner arp source ip             > Format : d.d.d.d']='7 14'
    insel_dict['inner arp target ip             > Format : d.d.d.d']='7 14'
    insel_dict['inner arp source mac            > Format : aaaa.bbbb.cccc']='7'
    insel_dict['inner arp target mac            > Format : aaaa.bbbb.cccc']='7 14'
    insel_dict['inner ipv4 source ip            > Format : d.d.d.d']='7 14'
    insel_dict['inner ipv4 destination ip       > Format : d.d.d.d']='7 14'
    insel_dict['inner ipv4 dscp                 > Format : 0-64']='7 14'
    insel_dict['inner ipv4 protocol             > Format : 0-255']='7 14'
    insel_dict['inner ipv6 destination ip       > Format : A:B::C:D']='7 14'
    insel_dict['inner ipv6 source ip            > Format : A:B::C:D']='7 14'
    insel_dict['inner ipv6 next-header          > Format : 0-255']='7 14'
    insel_dict['inner l4 source port            > Format : 0-65535']='7 14'
    insel_dict['inner l4 dest port              > Format : 0-65535']='7 14'
    insel_dict['inner l4 flags                  > Format : 0x0-0xff']='7'

    #Iterate through the above dictionaries and save the matching conditions to /tmp/elam_conditions
    c1=10; c2=20; c3=30; c4=40; c5=50; c6=60; c7=70; c8=80
    for key in "${!condition_dict[@]}"; do
        for k in "${!insel_dict[@]}"; do

            if grep -q "$key" <<< $k; then
                IFS=', ' read -r -a INSEL_LIST <<< "${insel_dict[$k]}"
                for i in "${INSEL_LIST[@]}"; do
                    if [[ $i == $insel ]]; then
                
                        if [[ $key =~ "outer l2" ]]; then
                            echo "$c1. $k" >> /tmp/elam_conditions
                            c1=$((c1+1))
                        fi
                        if [[ $key =~ "outer arp" ]]; then
                            echo "$c2. $k" >> /tmp/elam_conditions
                            c2=$((c2+1))
                        fi
                        if [[ $key =~ "outer ip" ]]; then
                            echo "$c3. $k" >> /tmp/elam_conditions
                            c3=$((c3+1))
                        fi
                        if [[ $key =~ "outer l4" ]]; then
                            echo "$c4. $k" >> /tmp/elam_conditions
                            c4=$((c4+1))
                        fi
                        if [[ $key =~ "inner l2" ]]; then
                            echo "$c5. $k" >> /tmp/elam_conditions
                            c5=$((c5+1))
                        fi
                        if [[ $key =~ "inner arp" ]]; then
                            echo "$c6. $k" >> /tmp/elam_conditions
                            c6=$((c6+1))
                        fi
                        if [[ $key =~ "inner ip" ]]; then
                            echo "$c7. $k" >> /tmp/elam_conditions
                            c7=$((c7+1))
                        fi
                        if [[ $key =~ "inner l4" ]]; then
                            echo "$c8. $k" >> /tmp/elam_conditions
                            c8=$((c8+1))
                        fi
                    fi
                done
            fi
        done
    done

    cat /tmp/elam_conditions | sort
    cat << 'EOF'

    Select corresponding numbers of conditions to set. Separate numbers with commas.
    Ex: 1,2,3,4,5
EOF
    read -p "Enter selections: "  'CONDITION_STR'
    IFS=', ' read -r -a CONDITION_LIST <<< "$CONDITION_STR"

    unset condition
    for e in "${CONDITION_LIST[@]}"; do
        if ! egrep -ql "^\s*$e\." /tmp/elam_conditions; then
            echo "Selection $e was not valid"
        else
            if [[ -v condition ]]; then
                condition+=$'\n'
            fi
            b=$(egrep "^$e\." /tmp/elam_conditions | sed -re 's/^[[:digit:]]+\.[[:blank:]]+(.*)$/\1/' | xargs)
            c=$(echo "$b" | sed -E 's/[[:space:]]+>.*$//g')
            read -p "Enter $b: "  'condition_value'
            condition+=${condition_dict[$c]}
            condition+=" $condition_value"
        fi
    done
}

function get_asic_slice() {
    if [[ -v interface ]]; then
        #this maps to interface, asic, slice, ssid, ovec
        if egrep -q "^$interface\s" /tmp/mod$mod-mappings; then
            asics=$(egrep "^$interface\s" /tmp/mod$mod-mappings | awk '{print $2}')
            slice=$(egrep "^$interface\s" /tmp/mod$mod-mappings | awk '{print $3}')
            srcid=$(egrep "^$interface\s" /tmp/mod$mod-mappings | awk '{print $4}')
            set_slice="slice"
        fi
    else
        #Get all asics on the card
        asics=$(cat /tmp/mod$mod-mappings | awk '{print $2}' | sort | uniq)
    fi
}

function set_elam() {
    mod_type=$(icurl 'http://localhost:7777/api/class/eqptCh.json?query-target=children&target-subtree-class=eqptFCSlot,eqptLCSlot&query-target-filter=or(and(eq(eqptFCSlot.physId,"'$mod'"))and(eq(eqptLCSlot.physId,"'$mod'")))' 2>/dev/null | egrep -o "eqpt[F,L]CSlot")
    
    if [[ $mod_type == "eqptLCSlot" ]]; then
        if [[ $direction == "ingress" ]]; then
            condition2=$condition
            condition2+=$'\n'
            condition2+="set outer l2 vntag_vld 0"
        elif [[ $direction == "egress" ]]; then
            condition2=$condition
            condition2+=$'\n'
            condition2+="set outer l2 vntag_vld 1"
        elif ! [[ -v direction ]]; then
            condition2=$condition
        fi
    elif [[ $mod_type == "eqptFCSlot" ]]; then
        condition2=$condition
    fi

    ssh_util "$mod"
    plat=${asic_dict[$mod]}
    get_asic_slice
    for asic_id in $asics; do
        bash << EOF 1>/dev/null
            $ssh_command  | tee /tmp/elam_output-mod$mod
            debug platform internal $plat elam asic $asic_id $set_slice $slice
            trigger reset
            trigger init in-select $insel out-select $outsel
            $condition2
            start
EOF
    done
}

function check_elam_status {
    rm -f /tmp/elam_output-mod$mod
    ssh_util "$mod"
    plat=${asic_dict[$mod]}
    get_asic_slice
    for asic_id in $asics; do
        bash << EOF 1>/dev/null
            $ssh_command  | tee -a /tmp/elam_output-mod$mod
            debug platform internal $plat elam asic $asic_id $set_slice $slice
            trigger init in-select $insel out-select $outsel
            stat
EOF
    done

    if grep -q "Triggered" /tmp/elam_output-mod$mod; then
        touch /tmp/triggered
        echo -e "\n"
        echo "ELAM TRIGGERED on module $mod:"
        grep "Triggered" /tmp/elam_output-mod$mod | awk '{print "ASIC: " $2 " SLICE: " $4}'
        if [[ -v interface ]]; then
            echo "INTERFACE: $interface"
        fi
        echo -e "\n"
        
        for t in $(grep "Triggered" /tmp/elam_output-mod$mod | awk '{print $2}' | sort | uniq); do echo "$mod $t" >> /tmp/trigList; done
    fi
}

function get_elam_report {
    ssh_util "$mod"
    plat=${asic_dict[$mod]}
    
    bash << EOF 1>/dev/null
        $ssh_command
        debug platform internal $plat elam asic $as
        trigger init in-select $insel out-select $outsel
        $report
EOF

    elam_report="/data/techsupport/mod$mod-asic$as-elamreport-$TS"
    scp -q -o ControlPath=/tmp/ssh-root@mod$mod:22 root@mod$mod:/var/sysmgr/tmp_logs/elam_report.txt $elam_report
    log "Module $mod Asic $as report saved to - $elam_report"
}

function get_hal_outputs() {
    ssh_util "$mod"
    echo "show platform internal hal l2 port gpd" > /tmp/hal_output-mod$mod
    bash << EOF 1>/dev/null
        $ssh_command | tee -a /tmp/hal_output-mod$mod
        show platform internal hal l2 port gpd
EOF
    echo "show platform internal hal l2 internal-port pi" >> /tmp/hal_output-mod$mod
    bash << EOF 1>/dev/null
        $ssh_command | tee -a /tmp/hal_output-mod$mod
        show platform internal hal l2 internal-port pi
EOF
}

function get_mod_list() {
    icurl 'http://localhost:7777/api/class/eqpt'$1'Slot.json?rsp-subtree=children&rsp-subtree-filter=eq(eqpt'$1'.rdSt,"active")&rsp-subtree-include=required' 2>/dev/null | python -m json.tool | grep physId | egrep -o "[0-9]+"
}

function close_ssh_sockets() {
    log "Closing existing ssh sockets..."
    for mod in $modList; do
        ssh -O stop -o controlPath=/tmp/ssh-root@mod$mod:22 root@mod$mod 2>/dev/null
    done
}

#####HELP
function display_help() {
    echo -e \\n"Help documentation for $0"\\n
    echo "****************************************************************************************************"
    echo "This script automates elams on gen2 and later modular spines. Unless an interface is specified, the"
    echo "tool will run elams on all asics for each module specified by the -m option in order to quickly find"
    echo "out the path of the packet through each module."
    echo ""
    echo "Note, this script doesn't do elam parsing/interpretation, it is intended only to collect the elams."
    echo -e "\n"
    echo "Supported Options:"
    echo "m:    (Required) Specify a comma-separated list of modules to run the elam on. Use keywords all to run on"
    echo "      all modules. Keyword lc or fc/fm can be used to select all LC's or FM's."
    echo "i:    Specify the front-panel ingress interface to match in the elam. Example: -i 2/10. If specified"
    echo "      specify only the one module using the -m option that contains this interface."
    echo "d:    Specify direction (for line card elams). 'ingress' captures traffic arriving from a front- "
    echo "      panel port. 'egress' captures traffic arriving from an FM. Not supported with in-select 7."
    echo "      By default the direction is set to ingress."
    echo "r:    Don't arm new elam, check on specified modules for previously triggered elams."
    echo "o:    Specify out-select (0 or 1). By default 1 is used. In most cases this is sufficient. For scenarios "
    echo "      where met pointer and other flood programming is being checked, use 0."
    echo "n:    Specify in-select (6,7, or 14). Use 6 to match outer headers or non vxlan encap'd traffic. Use 14 "
    echo "      to match outer or inner headers. Use 7 to only match inner conditions. Available conditions that"
    echo "      can be set will change based on in-select value. Default value is 14."
    echo "k:    If the script doesn't complete on a previous run it may leave open ssh sockets. This option closes"
    echo "      previous ssh sockets. Note, that these old sockets are checked for when running the script so there"
    echo "      should be no need to use this option."
    echo ""
    echo "Example Usage:"
    echo "      ./easy-spine-elam -m 2,3 -d ingress  <--check for traffic arriving from front panel on modules 2 and 3"
    echo "      ./easy-spine-elam -m all             <--check for traffic arriving from front-panel on all lc's and fm's"
    echo "      ./easy-spine-elam -m lc -d egress    <--check for traffic arriving on all LC's from fm's"
    echo "      ./easy-spine-elam -m fm              <--check all FM's for traffic"
    echo "      ./easy-spine-elam -m 2 -i 2/10       <--check for traffic arriving on module 2, interface eth2/10"
    echo "      ./easy-spine-elam -m all -r          <--check all modules for previously triggered elams"
    echo "      ./easy-spine-elam -m all -o 0 -n 6   <--check all modules using in-select 6 and out-select 0"
    echo ""
    echo "****************************************************************************************************"
    exit 0
}

##################
##################
#MAIN BODY BEGINS#
##################
##################
if [[ "$1" == "--help" ]] || [[ "$1" == "--h" ]]; then
    display_help
    exit 0
fi

###Clean up old files from past runs
rm -f /tmp/trigList
rm -f /tmp/hal_output-mod*
rm -f /tmp/elam_output-mod*
rm -f /tmp/elam_conditions
rm -f /tmp/mod*-mappings
rm -f /tmp/triggered

#####Take Args from Command
optspec="m:i:d:ro:n:kh"
while getopts "$optspec" optchar; do
  case $optchar in
    m)
        #module number
        if [[ $OPTARG == "all" ]]; then
            modList=$(get_mod_list "LC")
            modList+=" "
            modList+=$(get_mod_list "FC")
        elif [[ $OPTARG == "lc" ]]; then
            modList=$(get_mod_list "LC")
        elif [[ $OPTARG == "fc" ]] || [[ $OPTARG = "fm" ]]; then
            modList=$(get_mod_list "FC")
        elif [[ $OPTARG =~ , ]]; then
            modList=$(echo "$OPTARG" | sed -e "s/,/ /g")
            if [[ $modList =~ ^\s*$ ]]; then
                log "No modules specified. Please specify module(s) with the -m option. If multiple are specified then use a comma-separated list."
                log "Exiting..."
                exit 1
            fi
            
            for mod in $modList; do
                if ! [[ $mod =~ ^[0-9]+$ ]]; then
                    log "$mod is in invalid format. Should be the number of the module id."
                    log "Exiting..."
                    exit 1
                fi
            done
        elif [[ $OPTARG =~ ^[0-9]+$ ]]; then
            mod=$OPTARG
            modList=$OPTARG
        else
            log "$OPTARG is in invalid format. Should be the number of the module id."
            log "Exiting..."
            exit 1
        fi

        #Remove duplicate and invalid modules
        all_modules=$(get_mod_list "LC")
        all_modules+=" "
        all_modules+=$(get_mod_list "FC")
        read -r -a modArray <<< $modList
        e=0
        for mod in $modList; do
            unset exists
            for a in $all_modules; do
                if [[  $mod == $a ]]; then
                    exists="yes"
                    break
                fi
            done
            if ! [ -v exists ]; then
                #remove mod from list
                log "Module $mod doesn't exist. Removing"
                unset modArray[$e]
            fi
            let e++
        done
        modList=$(printf "%s\n" "${modArray[@]}" | sort -u)
        modList=$modList
        if [[ $modList =~ ^\s*$ ]]; then 
            log "No existing LC or FM modules were found. Exiting..."; exit 1
        fi
        echo "Final module list is:"
        echo $modList
        ;;
    i)
        #interface
        interface=$OPTARG
        if ! [[ $interface =~ ^[0-9]+\/[0-9]+$ ]]; then
            log "$interface is wrong format. Should be in the format of mod/port - ex: -i 1/2"
            log "Exiting..."
            exit 1
        fi
        ;;
    d)
        #direction, ingress or egress
        if [[ $OPTARG == "ingress" ]] || [[ $OPTARG == "egress" ]]; then
            direction=$OPTARG
        else
            log "Direction $OPTARG is not valid. Direction should be set to ingress or egress.."
        fi
        ;;
    r)
        #check status and get existing report. If r is not set then script will prompt to arm new elam. 
        action="report"
        ;;
    o)
        #Specify out-select. Default is 1
        outsel=$OPTARG
        ;;
    n)
        #Specify in-select value. Default is 14
        insel=$OPTARG
        ;;
    k)
        #If script was previously closed before finishing, socket files may still be open. While these shouldn't cause a problem, the -r option with -m all should close all existing ssh sockets that were created.
        close_sockets=yes
        ;;
    h)
        display_help
        exit 0
        ;;
    :)
        echo "Option $OPTARG requires an argument." >&2
        exit 1
        ;;
    \?)
        echo "Invalid option: \"-$OPTARG\"" >&2
        exit 1
        ;;
  esac
done

#####################################
#Define Variables and Do Validations#
#####################################
if ! [[ -v outsel ]]; then
    outsel=1
fi
if ! [[ -v insel ]]; then
    insel=14
fi

if ! [[ $outsel == "0" ]] && ! [[ $outsel == "1" ]]; then
    log "Out-select value was invalid. Use 0 or 1. Exiting..."
    exit 1
fi

if ! [[ $insel == "6" ]] && ! [[ $insel == "7" ]] && ! [[ $insel == "14" ]]; then
    log "In-select value was invalid. Use 6, 7, or 14. Exiting..."
    exit 1
fi
    
    

#Additional Validations
if [[ $close_sockets == "yes" ]]; then
    close_ssh_sockets
    exit 0
fi

if egrep -q "\/tmp\/ssh\-root\@mod[0-9]+:22.*mux" <<< "$(ps -ef)"; then
    log "Previous ssh sockets from past script runs exist. Closing them out then continuing..."
    close_ssh_sockets
fi

if ! [[ -v modList ]]; then
    log "No modules specified. Please specify module(s) with the -m option. If multiple are specified then use a comma-separated list."
    log "Exiting..."
    exit 1
fi

if ! [[ -v action ]]; then
    action="start"
fi

if ! [[ -v direction ]] || [[ -v interface ]]; then
    if [[ $direction == "egress" ]] && [[ -v interface ]]; then
        log "Ingress interface specified but direction set to egress. This is not valid...changing direction to ingress."
    elif ! [[ -v direction ]]; then
        log "Direction not specified. Setting to ingress."
    fi
    direction="ingress"
fi

if [[ -v direction ]] && [[ $insel == "7" ]]; then
    log "Direction is not supported with in-select 7. Matching packets will be caught going to and coming from the FM's."
    unset direction
fi

if [ $(wc -w <<< $modList) -gt 1 ] && [[ -v interface ]]; then
    log "When specifying the interface with the -i option, please only specify the module number that the interface exists on. Exiting..."
    exit 1
fi

#Build dictionary to map each module id to the asic family used for elams
log "In-select - $insel and out-select - $outsel are being used."
log "Gathering required hardware information..."
modList2=$(icurl 'http://localhost:7777/api/class/eqptLCSlot.json?rsp-subtree=children&rsp-subtree-filter=eq(eqptLC.rdSt,"active")&rsp-subtree-include=required' 2>/dev/null | python -m json.tool | grep physId | egrep -o "[0-9]+")
modList2+=" "
modList2+=$(icurl 'http://localhost:7777/api/class/eqptFCSlot.json?rsp-subtree=children&rsp-subtree-filter=eq(eqptFC.rdSt,"active")&rsp-subtree-include=required' 2>/dev/null | python -m json.tool | grep physId | egrep -o "[0-9]+")
declare -A asic_dict
for mod2 in $modList2; do
    asic=$(icurl 'http://localhost:7777/api/class/eqptCh.json?query-target=children&target-subtree-class=eqptFCSlot,eqptLCSlot&query-target-filter=or(and(eq(eqptFCSlot.physId,"'$mod2'"))and(eq(eqptLCSlot.physId,"'$mod2'")))&rsp-subtree=full&target-subtree-class=eqptSensor&rsp-subtree-filter=eq(eqptSensor.type,"asic")' 2>/dev/null | python -m json.tool | egrep "model.*instance" | awk -F "\"" '{print $4}' | awk '{print $1}' | uniq)
    
    if [[ $asic == "Sugarbowl" ]] || [[ $asic == "LAC" ]]; then
        asic_family=tah
    elif [[ $asic == "Homewood" ]]; then
        asic_family=roc
    elif [[ $asic == "Wolfridge" ]]; then
        asic_family=app
    fi

    asic_dict[$mod2]=$asic_family
done

#Gather hal outputs used for determing asics, slices, srcid, etc
#echo "modlist is $modList"
for mod in $modList; do
    get_hal_outputs &
done
wait

##Parse hal into interface to hw interface. Mapping of int asic slice srcid ovec is stored in /tmp/mod$modNumber-mappings
for mod in $modList; do
    if [ "$mod" -gt 20 ]; then
        #FC
        #this maps to interface, asic, slice, ssid, ovec
        grep -A 10000 "show platform internal hal l2 port gpd" /tmp/hal_output-mod$mod | grep -B 10000 "show platform internal hal l2 internal-port pi" | grep "fc" | sed -e 's/^.*fc/fc/g' | awk '{print $1" "$5" "$7" "$9" "$10}' > /tmp/mod$mod-mappings

    elif [ "$mod" -lt 20 ]; then
        #LC - front panel
        #this maps to interface, asic, slice, ssid, ovec
        grep -A 10000 "show platform internal hal l2 port gpd" /tmp/hal_output-mod$mod | grep -B 10000 "show platform internal hal l2 internal-port pi" | grep "Eth" | sed -e 's/^.*Eth//g' | awk '{print $1" "$5" "$7" "$9" "$10}' > /tmp/mod$mod-mappings
        
        #LC - internal
        #this maps to interface, asic, slice, ssid, ovec
        grep -A 10000 "show platform internal hal l2 internal-port pi" /tmp/hal_output-mod$mod | egrep "lc\([0-9]+\)\-fc\([0-9]+\)" | awk '{print $2" "$3" "$5" "$7" "$8}' >> /tmp/mod$mod-mappings
    fi
done

#Check if interface specified with -i option is valid.
for mod in $modList; do
    if [[ -v interface ]] && ! egrep -q "^$interface\s" /tmp/mod$mod-mappings; then
        log "Interface $interface not found in up state or does not exist on module $mod. Exiting..."
        close_ssh_sockets
        exit 1
    fi
done

#Build elam command and set it
if [[ $action == "start" ]]; then
    get_elam_conditions
    if ! [[ -v condition ]] && ! [[ -v interface ]]; then
        log "No conditions were set. Exiting..."
        close_ssh_sockets
        exit 1
    fi

    for mod in $modList; do
        log "Setting elam for module $mod"
        set_elam &
    done
    wait
fi

sleep 1

#Check elam status
check_status=status
while [[ $check_status == "status" ]]; do
    rm -f /tmp/trigList
    for mod in $modList; do
        log "Checking elam status for module $mod"
        check_elam_status &
    done
    wait
    if ! test -f "/tmp/triggered"; then
        echo -e "\nNO ELAMS HAVE TRIGGERED!\n"
    fi
    read -p 'Type "status" to check elam status again. Type "report" or "report detail" to collect all reports. Hit enter to finish: '  'check_status'
done

sleep 1

#If Elam has triggered, get the report.
if [[ $check_status == "report" ]] || [[ $check_status == "report detail" ]]; then
    report=$check_status
    if test -f "/tmp/triggered"; then
        TS=$(date '+%Y-%m-%dT%H-%M-%S')
        while IFS='' read -r line || [[ -n "$line" ]]; do
            mod=$(awk '{print $1}' <<< $line)
            as=$(awk '{print $2}' <<< $line)
            log "Collecting report for module $mod asic $as..."
            get_elam_report &
        done < /tmp/trigList
    else
        echo -e "\nNO ELAMS HAVE TRIGGERED!\n"
    fi
    wait
fi

#Clean up socket files
log "Cleaning up sockets..."
close_ssh_sockets
log "FINISHED!"
