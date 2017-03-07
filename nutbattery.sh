#!/bin/bash 

# NUTSpace NUT Mini Battery Service Inquiry
# -----------------------------------------
# Author: MrEmme
# ver.: 1.0
#
# INSTRUCTION
# -----------------------------------------
# This script will gather battery information
# from BLE device NUT Mini
# and update a Domoticz Variable with its value
# 
# Minimal user parameters are required:


# SETTING UP PARAMETERS
## DOMOTICZ SETUP (no authentication required, ensure that you have IP in whitelist)
DOMOIP="127.0.0.1"   # Domoticz Server IP 
DOMOPORT="8080"      # Domoticz Server Port

# DOMOTICZ STATUS INQUIRY
# Set to "1" if you want to check if the NUT switch is on before 
#            getting the battery data
# Set to anything else if you DO NOT want to check the status
#        and process all the NUT in the list (could take longer
#        and generate errors due to unavailability
DCHECKSTS="1"
# If a NUT is unaccessible enter the result string
# Otherwise it would be set to 0
BATTAWAYMSG="UNAVAILABLE"

# BEACON SERVICE DISCOVERY
# Battery and Beacon cannot coexist at the same time
# if you have a Beacon discovery service running
# this is the right place to identify it and 
# disable it while getting Batt information 
# Set to "1" if you want to disable the service
# Set to anything else if you DO NOT want to disable the service
USEBEACONSERVICE="1"
# Set the Service name 
BEACONSERVICENAME="beaconServiceName.service"
# INTERFACE NAME
# Once stopped the service, BLE interface needs to be resetted
# normally it is hci0
HCIINTERFACE="hci0"

# NUT LIST 
# Set the "MAC ADDRESS" "Domoticz Variable Name" "Switch IDX"
# each line is a NUT
# Add as many line as you need
NUTBATT=(
   "00:00:00:00:00:00" "Variabile_Nome_Batteria" "IDX switch ON/OFF"
)


# DO NOT CHANGE ANYTHING BEYOND THIS POINT
BATTUUID="0x2a19"   # UUID for Battery HEX Value
DAWVAR="/json.htm?type=command&param=updateuservariable&vname=VARIABLENAME&vtype=2&vvalue=VARIABLEVALUE"
DARDEV="/json.htm?type=devices&rid=DEVICEIDX"

function domoWriteVar () {
    URLREQ="http://"$DOMOIP":"$DOMOPORT$DAWVAR
    URLREQ="${URLREQ/VARIABLENAME/${NUTBATT[arrNut+1]}}"
    URLREQ="${URLREQ/VARIABLEVALUE/$1}"
    dzAPIWriteVar=$(curl -s "$URLREQ" ) 
 
}

function domoGetStatus {
    URLREQ="http://"$DOMOIP":"$DOMOPORT$DARDEV
    #echo $URLREQ
    dzAPIStatus="${URLREQ/DEVICEIDX/${NUTBATT[arrNut+2]}}"

# Getting switch status prom Domoticz
    dzDevRAW=$(curl -s "$dzAPIStatus")
    dzDevJSON=$(echo ${dzDevRAW} | jq .result[0].Data)
    dzDevSTATUS=$(echo $dzDevJSON | sed "s/\"//g")
}

function svcBeacon() {
    if [[ $1 == "stop" ]]; then
        echo "Stopping Beaconing Service"
        sudo systemctl stop ${BEACONSERVICENAME}
    fi
    
    if [[ $1 == "start" ]]; then
        echo "Starting Beaconing Service"
        sudo systemctl start ${BEACONSERVICENAME}
    fi
}

function restartHCI () {
    sudo hciconfig ${HCIINTERFACE} down 
    sleep 1 
    sudo hciconfig ${HCIINTERFACE} up 
}

function getBLEBat (){
    restartHCI

    HANDLE=$(sudo hcitool lecc --random ${NUTBATT[arrNut]} | awk '{print $3}')
    sleep 1
    sudo hcitool ledc $HANDLE
    BATHEX=$(sudo gatttool -t random --char-read --uuid $BATTUUID -b ${NUTBATT[arrNut]} | awk '{print $4}')
    BATDEC=$((0x$BATHEX))

    if [ "$BATDEC" == "0" ]; then
       BATDEC=$BATTAWAYMSG
    fi
    echo "Risultato finale: HEX :"$BATHEX" DEC: "$BATDEC
    domoWriteVar $BATDEC
}

# - - - - - - - - - - - 
# BEGINNING MAIN SCRIPT
# - - - - - - - - - - - 

if [[ $USEBEACONSERVICE == "1" ]]; then
    svcBeacon "stop"
fi

    printf "\n- - - - - - - - - - - - - - -\n" 

for arrNut in $(seq 0 3 $((${#NUTBATT[@]} - 1))); do
    if [[ $DCHECKSTS == "1" ]]; then
        domoGetStatus
        echo "Analyzing NUT: "${NUTBATT[arrNut+1]}" Domoticz State: "$dzDevSTATUS
    else
        dzDevSTATUS="On"
    fi
    
    if [[ $dzDevSTATUS == "On" ]]; then
        echo "Proceeding seeking for Battery Info"
        restartHCI
        getBLEBat
        dzDevSTATUS="Off"
    else
       echo "NUT Unavailable, skipping"
    fi 
    printf "\n- - - - - - - - - - - - - - -\n" 
done

if [[ $USEBEACONSERVICE == "1" ]]; then
    svcBeacon "start"
fi
