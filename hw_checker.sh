#!/bin/bash

##################
#Define Functions#
##################
function log() {
    ts=`date '+%Y-%m-%dT%H:%M:%S'`
    echo "$ts $1"
}

#Read lines from file $1 and see if they exist in HAL
function checker() {
    miss=0
    total_records=`wc -l < $1`
    curr_record=0
    
    while IFS='' read -r line || [[ -n "$line" ]]; do
        echo -ne "Progress $curr_record/$total_records\r"
        
        if [[ $node_role == "leaf" ]] || [[ $node_role == "fixed_spine" ]]; then
            if ! egrep -ql "$line" $2; then
                miss=1
                echo "$4 $line is missing from HAL."
            fi
        fi
        
        if [[ $node_role == "mod_spine" ]]; then
            #Check for missing EP's (synthetic vrf/ip)
            if [[ $1 == $coop_l3_records ]]; then
                synth_line=`echo $line | awk '{print $1" "$2}'`
                real_line=`echo $line | awk '{print $3" "$4}'`
                
                if ! egrep -ql "$synth_line" $synth_mod; then
                    miss=1
                    echo -e "$5 $real_line is missing hardware programming information"
                else
                    for ep_mod in `grep "$synth_line" $synth_mod | awk '{print $3}'`; do
                        if ! egrep -ql "$synth_line" /bootflash/mod"$ep_mod"-hal_l3_routes.txt; then
                            miss=1
                            echo -e "$4 $synth_line \t$5 $real_line is missing from HAL on FM $ep_mod"
                        fi
                    done
                fi
            
            #Check for missing mroute, uroute, etc
            else
                for mod in $modList; do
                    if ! egrep -ql "$line" /bootflash/mod"$mod"-hal_l3_routes.txt; then
                        miss=1
                        echo "$4 $line is missing from HAL on FM $mod"
                    fi
                done
            fi
        fi
        
        curr_record=$((curr_record+1))
        
    done < $1
    
    echo -ne "Progress $curr_record/$total_records\n"
    
    if [[ $miss == "0" ]]; then 
        log "All $3 were found in hardware."
    fi
}

function get_vrf_ids() {
    if [[ $node_role == "leaf" ]] ; then
        hal_ov_vrf_id=`icurl 'http://localhost:7777/api/mo/sys/inst-overlay-1.xml' 2>/dev/null | egrep -o "\sresourceId\=\"\S+" | awk -F "\"" '{print $2}'`
        
        #Map hw vrf id's to vrf names
        icurl 'http://localhost:7777/api/class/l3Ctx.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "hwResourceId\=\"[0-9]+\"|\sname\=\"\S+\"" | tr -d '\n' | sed 's/hwResourceId/\nhwResourceId/g' | egrep -v "^\s*$" | awk -F "\"" '{print $2" "$4}' | sort -k 1 > $vrf_keys
        echo "$hal_ov_vrf_id overlay-1" >> $vrf_keys
        
        #Map vrf vnids to vrf names
        icurl 'http://localhost:7777/api/class/l3Ctx.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "scope\=\"[0-9]+\"|\sname\=\"\S+\"" | tr -d '\n' | sed 's/name/\nname/g' | egrep -v "^\s*$" | awk -F "\"" '{print $4" "$2}' | sort -k 1 > $vrf_vnids
        echo "$ov_vrf overlay-1" >> $vrf_vnids
    fi
    
    if [[ $node_role == "fixed_spine" ]] || [[ $node_role == "mod_spine" ]] ; then
        icurl 'http://localhost:7777/api/class/coopCtxRec.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "vnid\=\"[0-9]+\"|\ctxName\=\"\S+\"" | tr -d '\n' | sed 's/ctxName/\nctxName/g' | egrep -v "^\s*$" | awk -F "\"" '{print $4" "$2}' | sort -k 1 > $vrf_vnids
        echo "$ov_hw_id overlay-1" >> $vrf_vnids
        echo "$ov_vrf overlay-1" >> $vrf_vnids
    fi
}

#Takes file $1 where first column is id of VRF (number), second column is name.
#Replaces id values in file $2 with matching vrf name from file $1.
function map_vrf_names() {
    for r in `awk '{print $1}' $1`; do 
        vrf_name=`egrep "^$r\s+" $1 | awk '{print $2}'`
        sed -re 's/^'$r'[[:blank:]]+/'$vrf_name' /' -i $2
    done
}

#Dump hal route table
function get_hal() {
    #Dump hal routes for single RU switches
    if [[ $node_role == "leaf" ]] || [[ $node_role == "fixed_spine" ]] ; then
        vsh_lc -c "show platform internal hal l3 routes v4" | egrep "TRIE|TCAM|DLEFT" | egrep "\sUC\||\sEP\||\sMC\|" | egrep "^\|\s*[0-9]+\|" | sort -k 1 | sed 's/|/ /g' | sed -re 's/^[[:blank:]]+//'  > $hal_routes
        
        #remove space in prefix
        sed -re 's/([[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\/)[[:blank:]]+/\1/' -i $hal_routes
        sed -re 's/^([^[:blank:]]+)[[:blank:]]+/\1 /' -i $hal_routes
        
        if [[ $node_role == "leaf" ]] ; then
            #Replace hwVrfId in HAL with actual vrf name
            map_vrf_names $vrf_keys $hal_routes
        fi
        
        if [[ $node_role == "fixed_spine" ]] ; then
            #Replace hwVrfId in HAL with actual vrf name
            map_vrf_names $vrf_vnids $hal_routes
        fi
    fi
    
    #Dump hal routes for each FM on modular spines
    if [[ $node_role == "mod_spine" ]] ; then
        for mod in $modList
            do
                file=/bootflash/mod"$mod"-hal_l3_routes.txt
                log "Collecting HAL routes from Fabric Module $mod..."
                vsh -c "slot $mod show platform internal hal l3 routes v4" | tr -d '\r' | egrep "TRIE|TCAM|DLEFT" | egrep "\sUC\||\sEP\||\sMC\|" | egrep "^\|\s*[0-9]+\|" | sort -k 1 | sed 's/|/ /g' > $file
                sed -re 's/([[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\/)[[:blank:]]+/\1/' -i $file
                sed -re 's/^[[:blank:]]+//' -i $file
                sed -re 's/^([^[:blank:]]+)[[:blank:]]+/\1 /' -i $file
                sed -re 's/^'$ov_hw_id' /overlay-1 /g' -i $file
            done
    fi
}

#Dump Software Routes from uribv4NextHop
function get_urib() {
    if [[ $node_role == "leaf" ]] ; then
        icurl 'http://localhost:7777/api/class/uribv4Nexthop.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "dn\=\"\S+\"" | egrep -v "\[local\]|\[coop\]" | sed 's/\/db-rt\/rt-\[/ /g' | awk -F "/" '{print $3"/"$4}' | sed 's/dom-//g' | sed 's/]$//g' | sort | uniq > $sw_routes
    fi
    
    #For spines only check consistency for overlay-1 routes. For other vrfs (mgmt, inb, span dest, etc) route is not in hal, but is in /proc/kic_database
    if [[ $node_role == "fixed_spine" ]] || [[ $node_role == "mod_spine" ]] ; then
        icurl 'http://localhost:7777/api/class/uribv4Nexthop.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "dn\=\"\S+\"" | grep "dom-overlay-1" | sed 's/\/db-rt\/rt-\[/ /g' | awk -F "/" '{print $3"/"$4}' | sed 's/dom-//g' | sed 's/]$//g' | sort | uniq > $sw_routes
    fi
}

#Dump Software Multicast routes from pimRoute and isisGrpRec
function get_mrib() {
    icurl 'http://localhost:7777/api/class/pimRoute.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "dn\=\"\S+\"" | awk -F "\"" '{print $2}' | sed 's/\/db-route.*grp-\[/ /g' | sed 's/^.*dom-//g' | sed 's/]$//g' | sort | uniq > $mc_routes
    
    if [[ $node_role == "leaf" ]]; then
        icurl 'http://localhost:7777/api/class/isisGrpRec.xml?rsp-subtree=children&rsp-subtree-class=isisOifListLeaf&rsp-subtree-include=required,no-scoped' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "dn\=\"\S+\"" | awk -F "\"" '{print $2}' | sed 's/\/lvl-l1.*grp-\[/ /g' | sed 's/^.*dom-//g' | sed 's/].*$/\/28/g' | grep -v fmtree | sort | uniq >> $mc_routes
    fi
    
    if [[ $node_role == "fixed_spine" ]] || [[ $node_role == "mod_spine" ]] ; then
        icurl 'http://localhost:7777/api/class/isisGrpRec.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "dn\=\"\S+\"" | awk -F "\"" '{print $2}' | sed 's/\/lvl-l1.*grp-\[/ /g' | sed 's/^.*dom-//g' | sed 's/].*$/\/32/g' | grep -v fmtree | sort | uniq >> $mc_routes
    fi
}

#Dump Software l3 ep's from epmIpEp
function get_ep() {
    icurl 'http://localhost:7777/api/class/epmIpEp.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "dn\=\"\S+\"" | awk -F "\"" '{print $2}' | egrep "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sed 's/^.*ctx-\[vxlan-//g' | sed -re 's/([[:digit:]]+).*ip-\[/\1 /' | sed 's/]$/\/32/g' | sed "s/^.*overlay-1/$ov_vrf/g" | sort -k 1 | uniq > $ep_routes
    
    #Remove epmIpEp objects with "span" flag set. These are only in hardware if hal
    #is the learn source and there's not a good way to verify that from software
    icurl 'http://localhost:7777/api/class/epmIpEp.xml?query-target-filter=wcard(epmIpEp.flags,"span")' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "dn\=\"\S+\"" | awk -F "\"" '{print $2}' | sed 's/^.*vxlan-//g' | sed -re 's/([[:digit:]]+).*ip-\[/\1 /' | sed 's/]$/\/32/g' | sed "s/^.*overlay-1/$ov_vrf/g" | sort -k 1 > /bootflash/span_ep.txt
    while IFS='' read -r line || [[ -n "$line" ]]; do
        e=`echo $line | sed -e "s/\//\\\\\\\\\//"`
        #echo $e
        sed -i "/$e/d" $ep_routes
    done < /bootflash/span_ep.txt
    
    #Replace vnids with vrf names to compare with hal
    map_vrf_names $vrf_vnids $ep_routes
}

#Dump Coop Layer 3 (IPv4) Records
function get_coop_records() {
    if [[ $node_role == "fixed_spine" ]]; then
        #Get coopIpv4Rec (these are non svi layer 3 endpoints)
        icurl 'http://localhost:7777/api/class/coopEpRec.xml?rsp-subtree=children&rsp-subtree-class=coopIpv4Rec&rsp-subtree-include=required' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "vrfVnid\=\"[0-9]+\"|\saddr\=\"\S+\"" | tr -d '\n' | sed 's/vrfVnid/\nvrfVnid/g' | egrep -v "^$" > /bootflash/coop_tmp.txt
    
        total_records=`icurl 'http://localhost:7777/api/class/coopEpRec.xml?rsp-subtree=children&rsp-subtree-class=coopIpv4Rec&rsp-subtree-include=no-scoped,count' 2>/dev/null | egrep -o "count\=\"\S+\"" | awk -F "\"" '{print $2}'`
        curr_record=0
    
        #Handle scenarios where there are multiple coopIpv4Rec's for a single coopEpRec
        log "Organizing COOP records. Large numbers of IP's learned on a small number of MACs will make this take longer..."
        while IFS='' read -r line || [[ -n "$line" ]]; do
            if [[ $curr_record -eq $total_records ]]; then
                continue
            else
                addr_list=($line)
                wc=${#addr_list[@]}
                    if [[ $wc -gt 2 ]]; then
                        v=${addr_list[0]}
                    
                        while [ "$wc" -ge 2 ] ; do    
                            echo "$v ${addr_list[1]}" >> /bootflash/coop_tmp.txt
                            unset 'addr_list[1]'
                            tmp=${addr_list[@]}
                            addr_list=($tmp)
                            wc=${#addr_list[@]}
                            echo -ne "Progress $curr_record/$total_records\r"
                            curr_record=$((curr_record+1))
                        done
                        
                        echo "/$line/d" > /bootflash/script.sed
                        sed -i -f /bootflash/script.sed /bootflash/coop_tmp.txt
                    else
                        echo -ne "Progress $curr_record/$total_records\r"
                        curr_record=$((curr_record+1))                        
                    fi    
            fi
        done < /bootflash/coop_tmp.txt
        
        echo -ne "Progress $curr_record/$total_records\n"
        
        awk -F "\"" '{print $2" "$4"/32"}' /bootflash/coop_tmp.txt | sort -k 1 > $coop_l3_records
        rm -f /bootflash/coop_tmp.txt
    
        #Get coopIpOnlyRec (these are non svi layer 3 endpoints)
        icurl 'http://localhost:7777/api/class/coopIpOnlyRec.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "vrfVnid\=\"[0-9]+\"|\saddr\=\"\S+\"" | tr -d '\n' | sed 's/addr/\naddr/g' | awk -F "\"" '{print $4" "$2"/32"}'  | egrep -v "^\s*$" | egrep "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort -k 1 >> $coop_l3_records
        
        #Replace vnids with vrf names (except for remote site ep's) to compare with hal
        map_vrf_names $vrf_vnids $coop_l3_records
    fi
    
    if [[ $node_role == "mod_spine" ]]; then
        #Get coopIpv4Rec (these are non svi layer 3 endpoints)
        #In hardware the syth vrf id base value is 500. So to compare hardware and software synthetic values need to add 500 to software value.
        icurl 'http://localhost:7777/api/class/coopEpRec.xml?rsp-subtree=children&rsp-subtree-class=coopIpv4Rec&rsp-subtree-include=required' 2>/dev/null | xmllint --format - 2>/dev/null | sed -re 's/^.*(vrfVnid\=\"[[:digit:]]+\").*$/\1/g' | egrep -o "synthVrf\=\"[0-9]+\"|\ssynthIp\=\"\S+\"|vrfVnid\=\"[0-9]+\"|addr\=\"\S+\"" | sed -re 's/^([^[:blank:]]+)/ \1/' | tr -d '\n' | sed -e 's/vrfVnid/\nvrfVnid/g' | egrep -v "^\s*$" > /bootflash/coop_tmp.txt
        
        total_records=`icurl 'http://localhost:7777/api/class/coopEpRec.xml?rsp-subtree=children&rsp-subtree-class=coopIpv4Rec&rsp-subtree-include=no-scoped,count' 2>/dev/null | egrep -o "count\=\"\S+\"" | awk -F "\"" '{print $2}'`
        curr_record=0
        #echo -e "\n"
    
        #Handle scenarios where there are multiple coopIpv4Rec's for a single coopEpRec
        log "Organizing COOP records. Large numbers of IP's learned on a small number of MACs will make this take longer..."
        while IFS='' read -r line || [[ -n "$line" ]]; do
            if [[ $curr_record -eq $total_records ]]; then
                continue
            else
                addr_list=($line)
                wc=${#addr_list[@]}
                    if [[ $wc -gt 4 ]]; then
                        v=${addr_list[0]}
                    
                        while [ "$wc" -ge 4 ] ; do
                            #echo $wc
                            echo "$v ${addr_list[1]} ${addr_list[2]} ${addr_list[3]}" >> /bootflash/coop_tmp.txt
                            unset 'addr_list[1]'
                            unset 'addr_list[2]'
                            unset 'addr_list[3]'
                            tmp=${addr_list[@]}
                            addr_list=($tmp)
                            wc=${#addr_list[@]}
                            echo -ne "Progress $curr_record/$total_records\r"
                            curr_record=$((curr_record+1))
                        done
                        
                        echo "/$line/d" > /bootflash/script.sed
                        sed -i -f /bootflash/script.sed /bootflash/coop_tmp.txt
                    else
                        echo -ne "Progress $curr_record/$total_records\r"
                        curr_record=$((curr_record+1))
                    fi

            fi
        done < /bootflash/coop_tmp.txt    
        
        echo -ne "Progress $curr_record/$total_records\n"
            
        awk -F "\"" '{print $8+500" "$6"/32 "$2" "$4}' /bootflash/coop_tmp.txt | sort -k 1 > $coop_l3_records
        rm -f /bootflash/coop_tmp.txt
        
        #Get coopIpOnlyRec (these are non svi layer 3 endpoints)
        icurl 'http://localhost:7777/api/class/coopIpOnlyRec.xml' 2>/dev/null | xmllint --format - 2>/dev/null | egrep -o "synthVrf\=\"[0-9]+\"|\ssynthIp\=\"\S+\"|vrfVnid\=\"[0-9]+\"|addr\=\"\S+\""    | tr -d '\n' | sed 's/addr/\naddr/g' | grep -v ":" | egrep -v "^\s*$" | awk -F "\"" '{print $6+500" "$4"/32 "$8" "$2}' | sort -k 1 >> $coop_l3_records

        #Find out which FM's each synthetic IP should exist on. Format of output file is <synth vrf id> <synthetic prefix> <mod> <asic>
        log "Checking which Fabric Modules should have each Synthetic IP..."
        any_mod=`moquery -c eqptFCSlot -f 'eqpt.FCSlot.operSt=="inserted"' | grep physId | awk '{print $3}' | head -1`
        vsh -c "slot $any_mod show forwarding route platform" | egrep "Prefix|FC\sCards|Synth" | grep -B 2 "FC Cards" | tr -d '\n' | sed -re 's/Prefix/\nPrefix/g' | sed 's/, Num_paths.*Vrf\=/ /g' | sed 's/\sSynth.*\s:\sFC/ /g' | sed -re 's/\s+FC/ /g' | sed 's/\/ASIC-/ /g' | sed 's/^Prefix://g' | egrep -v "^\s*$" | awk '{print $2" "$1" "$3" "$4"\n"$2" "$1" "$5" "$6}' > $synth_mod
        
        #Replace vnids with vrf names to easily see which real vrf and real ip a synthetic vrf and synthetic ip map to 
        map_vrf_names $vrf_vnids $coop_l3_records        
    fi
}

#####HELP
function display_help() {
    echo -e \\n"Help documentation for $0"\\n
    echo "****************************************************************************************************"
    echo "This script automates validation that IPv4 endpoints, IPv4 COOP records, unicast routes, and"
    echo "multicast routes are installed in hardware (HAL)"
    echo ""
    echo "Supported Options:"
    echo "e:    Verify hardware and software consistency for IPv4 endpoints."
    echo "u:    Verify hardware and software consistency for unicast IPv4 routes."
    echo "m:    Verify hardware and software consistency for multicast IPv4 routes."
    echo "c:    Verify hardware and software consistency for coop IPv4 records."
    echo "a:    Verify hardware and software consistency for all supported objects."    
    echo "****************************************************************************************************"
    exit 0
}


##################
#MAIN BODY BEGINS#
##################
if [[ "$1" == "--help" ]] || [[ "$1" == "--h" ]]; then
    display_help
    exit 0
fi

#####Take Args from Command
optspec="eumcah"
while getopts "$optspec" optchar; do
  case $optchar in
    e)
        v4ep=1
        ;;
    u)
        v4uroute=1
        ;;
    m)
        v4mroute=1
        ;;
    c)
        v4coop=1
        ;;
    a)
        all=1
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

#Validate all the necessary arguments exist
if [ -z ${v4ep+x} ] && [ -z ${v4uroute+x} ] && [ -z ${v4mroute+x} ] && [ -z ${v4coop+x} ] && [ -z ${all+x} ]; then 
    log "Arguments are required. Check the -h/--h/--help for options"
    exit 1
fi

##################
#Define Variables#
##################
sw_routes="/bootflash/sw_routes.txt"
mc_routes="/bootflash/mc_routes.txt"
ep_routes="/bootflash/ep_routes.txt"
coop_l3_records="/bootflash/coop_l3_records.txt"
hal_routes="/bootflash/hal_l3_routes.txt"
vrf_keys="/bootflash/vrf_keys.txt"
vrf_vnids="/bootflash/vrf_vnids.txt"
synth_mod="/bootflash/synth_mod.txt"
#Get seg id for overlay vrf
ov_vrf=`moquery -d sys/inst-overlay-1 | grep encap | awk -F "-" '{print $2}'`
#Get hw id for overlay vrf
ov_hw_id=`icurl 'http://localhost:7777/api/mo/sys/inst-overlay-1.xml' 2>/dev/null | egrep -o "\sid\=\"\S+" | awk -F "\"" '{print $2}'`

#determine if switch is leaf, fixed spine, or modular spine
node_role=`moquery -c topSystem -f "top.System.name==\"\`echo $HOSTNAME\`\"" | grep role | awk '{print $3}'`
if [[ $node_role == "spine" ]]; then
    if moquery -d sys/ch | egrep "^model.*N9K-C95" 1>/dev/null; then
        node_role=mod_spine
        modList=`moquery -c eqptFCSlot -f 'eqpt.FCSlot.operSt=="inserted"' | grep physId | awk '{print $3}'  | sed -e 'H;${x;s/\n/ /g;s/^\s//;p;};d'`
    elif moquery -d sys/ch | egrep "^model.*N9K-C93" 1>/dev/null; then
        node_role=fixed_spine
    else
        log "Node is a spine but couldn't determine if modular or fixed. Exiting..."
        exit 1
    fi
fi

#####################
#Initial Validations#
#####################
moquery -c eqptSilicon -f 'eqpt.Sensor.type=="asic"' | grep model | egrep "Alpine|Donner|Trident"
if [[ $? == "0" ]]; then
    log "This is a Gen 1 switch. This script is intended for Gen 2 or later. Exiting..."
    exit 1
fi

###########
#Main Body#
###########
log "Node Role is $node_role"

#exiting if only e option was selected (since this section is for spines)
if [[ $node_role == "leaf" ]]; then
    if [[ $v4coop == 1 ]] && ([ -z ${v4uroute+x} ] && [ -z ${v4mroute+x} ] && [ -z ${v4ep+x} ] && [ -z ${all+x} ]); then
        log "Only c / coop was selected. This is a leaf so that option doesn't make sense. Exiting..."
        exit 1
    fi    
fi    

#exiting if only e option was selected (since this section is for spines)
if [[ $node_role == "fixed_spine" ]] || [[ $node_role == "mod_spine" ]]; then
    if [[ $v4ep == 1 ]] && ([ -z ${v4uroute+x} ] && [ -z ${v4mroute+x} ] && [ -z ${v4coop+x} ] && [ -z ${all+x} ]); then
        log "Only e / endpoints were selected. This is a spine so that option doesn't make sense. Exiting..."
        exit 1
    fi    
fi    

if [[ $node_role == "leaf" ]] || [[ $node_role == "fixed_spine" ]] || [[ $node_role == "mod_spine" ]]; then 
    #Get vrf ID's
    log "Getting vrf ID's..."
    get_vrf_ids
    
    #Get software unicast routes
    if [[ $all == 1 ]] || [[ $v4uroute == 1 ]]; then
        log "Collecting IPv4 routes from URIB..."
        get_urib
    fi
    
    #Get software multicast routes
    if [[ $all == 1 ]] || [[ $v4mroute == 1 ]]; then
        log "Collecting IPv4 routes from MRIB..."
        get_mrib
    fi
    
    if [[ $node_role == "leaf" ]] ; then
        #Get layer 3 IPv4 endpoint information from EPM
        if [[ $all == 1 ]] || [[ $v4ep == 1 ]]; then
            log "Collecting layer 3 endpoints from EPM..."
            get_ep
        fi
        
        #Get routes from hal
        log "Collecting routes from HAL..."
        get_hal
        
        #Check for missing unicast v4 routes in hardware
        if [[ $all == 1 ]] || [[ $v4uroute == 1 ]]; then
            log "Checking for unicast ipv4 routes that are missing in hal..."
            checker $sw_routes $hal_routes "unicast ipv4 routes" "Unicast Route:"
        fi
        
        #Check for missing multicast routes in hardware
        if [[ $all == 1 ]] || [[ $v4mroute == 1 ]]; then
            log "Checking for multicast ipv4 routes that are missing in hal..."
            checker $mc_routes $hal_routes "multicast ipv4 routes" "Multicast Route:"
        fi
        
        #Check for missing ipv4 endpoints in hardware
        if [[ $all == 1 ]] || [[ $v4ep == 1 ]]; then
            log "Checking for ipv4 endpoints that are missing in hal..."
            checker $ep_routes $hal_routes "IPv4 endpoints"
        fi
        
    elif [[ $node_role == "fixed_spine" ]] ; then
        #Get COOP layer 3 (IPv4 records)
        if [[ $all == 1 ]] || [[ $v4coop == 1 ]]; then
            log "Collecting COOP IPv4 records..."
            get_coop_records
        fi
        
        #Get routes from hal
        log "Collecting routes from HAL..."
        get_hal
        
        #Check for missing unicast v4 routes in hardware
        if [[ $all == 1 ]] || [[ $v4uroute == 1 ]]; then
            log "Checking for unicast ipv4 routes that are missing in hal..."
            checker $sw_routes $hal_routes "unicast ipv4 routes" "Unicast Route:"
        fi
        
        #Check for missing multicast routes in hardware
        if [[ $all == 1 ]] || [[ $v4mroute == 1 ]]; then
            log "Checking for multicast ipv4 routes that are missing in hal..."
            checker $mc_routes $hal_routes "multicast ipv4 routes" "Multicast Route:"
        fi
    
        #Check for missing EP v4 records in hardware
        if [[ $all == 1 ]] || [[ $v4coop == 1 ]]; then
            log "Checking for COOP ipv4 records that are missing in hal..."
            checker $coop_l3_records $hal_routes "COOP IPv4 Records"
        fi
    
    elif [[ $node_role == "mod_spine" ]] ; then
        #Get COOP layer 3 (IPv4 records)
        if [[ $all == 1 ]] || [[ $v4coop == 1 ]]; then
            log "Collecting COOP IPv4 records..."
            get_coop_records
        fi
        
        #Get routes from hal
        get_hal
        
        #Check for missing unicast v4 routes in hardware
        if [[ $all == 1 ]] || [[ $v4uroute == 1 ]]; then
            log "Checking for unicast ipv4 routes that are missing in hal..."
            checker $sw_routes "empty" "unicast ipv4 routes" "Unicast Route:"
        fi
        
        #Check for missing multicast routes in hardware
        if [[ $all == 1 ]] || [[ $v4mroute == 1 ]]; then
            log "Checking for multicast ipv4 routes that are missing in hal..."
            checker $mc_routes "empty" "multicast ipv4 routes" "Multicast Route:"
        fi
    
        #Check for missing COOP v4 records in hardware
        if [[ $all == 1 ]] || [[ $v4coop == 1 ]]; then
            log "Checking for COOP ipv4 records that are missing in hal..."
            checker $coop_l3_records "empty" "COOP IPv4 Records" "Synthetic IP:" "Real IP:"
        fi
    fi
fi
