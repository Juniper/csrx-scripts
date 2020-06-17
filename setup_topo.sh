#!/bin/bash

#docker network name
BR_MANAGMENT="br-csrx-mng"
BR_CSRX_ETH1="br-csrx-eth1"
BR_CSRX_ETH2="br-csrx-eth2"
#host interface added to BR_CSRX_ETH1
NIC1='eth1'
#host interface added to BR_CSRX_ETH2
NIC2='eth2'

# this tool helps to build a topology like below:
topology_str="

                                 ge-0/0/0(eth1)     ge-0/0/1(eth2)
                                   +-----------------+     
 $NIC1-----$BR_CSRX_ETH1-----------|       cSRX      |---------------$BR_CSRX_ETH2-----$NIC2
                                   +--------+--------+        
                                            | eth0
                                            |
                                            |
                                      $BR_MANAGMENT 
"

#cSRX running environment variable define

#cSRX container name
CONTAINER_CSRX='csrx'
#cSRX image name
IMAGE_CSRX='csrx:latest'
# management network subnet 
MGMT_SUBNET='172.31.12.0/24'
#external SSH port, use "ssh -p <EXT_SSH_PORT> HOST_ADDR" to 
#access from outside
EXT_SSH_PORT=2222

#cSRX env variable define
#auto assign pod ip to cSRX interface
#CSRX_AUTO_ASSIGN_IP="yes"
#cSRX mgmt port reorder to last pod interface
#CSRX_MGMT_PORT_REORDER="yes"
#recompute tcp checksum in cSRX
CSRX_TCP_CKSUM_CALC="yes"
#cSRX packet drive mode
CSRX_PACKET_DRIVER="interrupt"
#CSRX_PACKET_DRIVER="poll"
#CSRX_FORWARD_MODE
CSRX_FORWARD_MODE="routing"
#CSRX_FORWARD_MODE="wire"
#cSRX root password
CSRX_ROOT_PASSWORD="Password"


#utility tools
function add_host_interface_to_bridge()
{
    linux_bridge=br-$(docker network ls|grep $1| awk -F ' ' '{print $1}')
    if [ ! -z "$linux_bridge" ]
    then
       brctl addif "$linux_bridge" "$2"
    fi   
}

function csrx_start()
{
    #start cSRX and attach to docker network
    echo "Building cSRX topology:"
    echo "$topology_str"
    echo "Starting csrx container '$CONTAINER_CSRX'..."

    # Create docker network
    echo "Creating network '$BR_MANAGMENT'..."
    docker network create --driver=bridge --subnet=$MGMT_SUBNET "$BR_MANAGMENT"
    echo "Creating network '$BR_CSRX_ETH1'..."
    docker network create --driver=bridge "$BR_CSRX_ETH1"
    echo "Creating network '$BR_CSRX_ETH2'..."
    docker network create --driver=bridge "$BR_CSRX_ETH2"

    #start cSRX container, customized env variable according to deployment
    docker run -d --privileged --name "$CONTAINER_CSRX"  -p $EXT_SSH_PORT:22 \
        -e CSRX_ROOT_PASSWORD="$CSRX_ROOT_PASSWORD" -e CSRX_PACKET_DRIVER="$CSRX_PACKET_DRIVER" \
        -e CSRX_FORWARD_MODE="$CSRX_FORWARD_MODE" -e CSRX_TCP_CKSUM_CALC="yes" \
        --net=$BR_MANAGMENT   "$IMAGE_CSRX"

    # Configure csrx container
    echo "Configuring $CONTAINER_CSRX ..."
    docker network connect  $BR_CSRX_ETH1 $CONTAINER_CSRX
    docker network connect  $BR_CSRX_ETH2 $CONTAINER_CSRX

    add_host_interface_to_bridge $BR_CSRX_ETH1 $NIC1
    add_host_interface_to_bridge $BR_CSRX_ETH2 $NIC2

    # Configure iptables rule
    iptables -P FORWARD ACCEPT

    echo "docker ps"
    docker ps
}

function csrx_stop()
{
    echo "Stopping container $CONTAINER_CSRX ..."
    csrx_running=`docker ps --format='{{.Names}}' | egrep "^$CONTAINER_CSRX$"`
    csrx_exist=`docker ps -a --format='{{.Names}}' | egrep "^$CONTAINER_CSRX$"`
    if [ ! -z "$csrx_running" ]
    then
        docker stop "$CONTAINER_CSRX"
    fi

    if [ ! -z "$csrx_exist" ]
    then
        docker rm -v "$CONTAINER_CSRX"
    fi


    echo "Delete docker network $BR_MANAGMENT $BR_CSRX_ETH1 $BR_CSRX_ETH2"
    docker network rm "$BR_MANAGMENT"
    docker network rm "$BR_CSRX_ETH1"
    docker network rm "$BR_CSRX_ETH2"

    echo "docker ps"
    docker ps
}

if [ -z "$1" ] || [ "$1" = "start" ]
then
   csrx_start
elif [ "$1" = "stop" ]
then
   csrx_stop
fi

