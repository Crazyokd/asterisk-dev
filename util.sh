#!/bin/env bash

# Usage:
#    bridge: ./util.sh -c clearChannels,clearBridges,createAndBridgeChannels --ip 172.16.16.20
#    websockt: ./util.sh -c connect --ip 172.16.16.20

# normalize command line arguments
TEMP=$(getopt -o c:k:h -l command:,key:,help,ip: -n '$0' -- "$@")

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# 重新设置命令行参数
eval set -- "$TEMP"
# ref to https://stackoverflow.com/questions/402377/using-getopts-to-process-long-and-short-command-line-options
# If you delete above lines (everything up through the eval set line), the code will still work!
# However, your code will be much pickier in what sorts of options it accepts.
# In particular, you'll have to specify all options in the "canonical" form described above.
# With the use of getopt, however, you can group single-letter options, use shorter non-ambiguous forms of long-options.
# getopt also outputs an error message if unrecognized or ambiguous options are found.

default_ip=192.168.70.128
api_key="asterisk:passwd"
app=test

function show_help() {
    echo "Usage: $0 -c commands [-k <key>] [-ip <ip>] [-h]"
    echo "  -c <commands>    commands to be executed"
    echo "  --ip <ip>         IP address of the server (default: $default_ip)"
    echo "  -h               Show this help message"
}

# set -x
while true; do
    case "$1" in
        -c | --command ) commands="$2"; shift 2 ;;
        -k | --key ) api_key="$2"; shift 2 ;;
        -h | --help ) show_help; exit 0 ;;
        --ip ) default_ip="$2"; shift 2 ;;
        * ) break ;;
    esac
done

base_url="http://$default_ip:8088/ari"
bridge_id=123
channel1_id=123
channel2_id=456
user1=0000f30A0A01
user2=0000f30B0B02

if [ -z "$commands" ]; then
    show_help
    exit 1
fi

# clear all channels
function clearChannels() {
    local channels_response
    channels_response=$(curl -s -G "$base_url/channels" --data-urlencode "api_key=$api_key")

    if [[ $? -ne 0 ]]; then
        echo "Failed to retrieve channels list"
        return 1
    fi

    local channel_ids
    channel_ids=$(echo "$channels_response" | jq -r '.[].id')

    if [[ -z "$channel_ids" ]]; then
        echo "No channels found"
        return 0
    fi

    for channel_id in $channel_ids; do
        local delete_response
        delete_response=$(curl -s -X DELETE "$base_url/channels/$channel_id" --data-urlencode "api_key=$api_key")

        if [[ $? -ne 0 ]]; then
            echo "Failed to delete channel with ID: $channel_id"
        else
            echo "Successfully deleted channel with ID: $channel_id"
        fi
    done
}

function clearBridges() {
    local bridges_response
    bridges_response=$(curl -s -G "$base_url/bridges" --data-urlencode "api_key=$api_key")

    if [[ $? -ne 0 ]]; then
        echo "Failed to retrieve bridges list"
        return 1
    fi

    local bridge_ids
    bridge_ids=$(echo "$bridges_response" | jq -r '.[].id')

    if [[ -z "$bridge_ids" ]]; then
        echo "No bridges found"
        return 0
    fi

    for id in $bridge_ids; do
        local delete_response
        delete_response=$(curl -s -X DELETE "$base_url/bridges/$id" --data-urlencode "api_key=$api_key")

        if [[ $? -ne 0 ]]; then
            echo "Failed to delete bridge with ID: $id"
        else
            echo "Successfully deleted bridge with ID: $id"
        fi
    done
    return 0
}

# record and generate recording file
# $1: bridgeId
function record() {
    local fn=$(date +"%Y-%m-%d")
    local record_response=$(curl -s -G -X POST "$base_url/bridges/$1/record?format=wav&ifExists=overwrite&terminateOn=none&api_key=$api_key" --data-urlencode "name=$fn")

    if [[ $? -ne 0 ]]; then
        echo "Failed to record in bridge($1)"
        return 1
    fi

    echo "Successfully start record in bridge($1)"
}

# $1: channelId, $2: bridgeId
function add_channel_to_bridge() {
    local max_retry=25
    local retry=0
    while true; do
        local channel_status_response
        channel_status_response=$(curl -s -G "$base_url/channels/$1" --data-urlencode "api_key=$api_key")
        local state=$(echo "$channel_status_response" | jq -r '.state')
        if [[ "$state" == "Up" ]]; then
            break
        fi
        retry=$((retry+1))
        if [ $retry -eq $max_retry ]; then
            return 2
        fi
        sleep 1
    done
    local add_channel_response
    add_channel_response=$(curl -s -X POST "$base_url/bridges/$2/addChannel?channel=$1&api_key=$api_key")
    if [[ $? -ne 0 ]]; then
        echo "Failed to add channel $1 to bridge"
        return 1
    fi
    echo "Successfully add $1 to bridge"
}

function createBridge() {
    local bridge_response
    bridge_response=$(curl -s -X POST "$base_url/bridges/$1?api_key=$api_key")

    return $?
}

function answerChannel() {
    $(curl -s -X POST "$base_url/channels/$1/answer?api_key=$api_key")
    return $?
}

# play a sound
# $1: bridgeId
function play() {
    local sound=busy-hangovers
    local play_response=$(curl -s -X POST "$base_url/bridges/$1/play?skipms=3000&api_key=$api_key" --data-urlencode "media=sound:$sound")

    if [[ $? -ne 0 ]]; then
        echo "Failed to play in bridge($1)"
        return 1
    fi

    echo "Successfully play $sound in bridge($1)"
}

# $1: user, $2: channelId
function createChannel() {
    local channel_response
    channel_response=$(curl -s -X POST "$base_url/channels?endpoint=SIP%2F$1%40WCDMA1&app=$app&timeout=30&channelId=$2&api_key=$api_key")

    return $?
}

function bridgeCalled() {
    local channel1=1738821091.65 # channel.caller.number
    local channel2=888 # channel.dialplan.exten
    local callee=18601234514

    # 删除channel2
    curl -s -X DELETE "$base_url/channels/$channel2" --data-urlencode "api_key=$api_key"
    # 获取channelId（这里只是简单的获取第一个channel的Id）
    channels_response=$(curl -s -G "$base_url/channels" --data-urlencode "api_key=$api_key")
    if [[ $? -ne 0 ]]; then
        echo "Failed to retrieve channels list"
        return 1
    fi
    channel1=$(echo "$channels_response" | jq -r '.[0].id')

    createChannel $callee $channel2
    if [[ $? -ne 0 ]]; then
        echo "Failed to create channel 1"
        return 1
    fi

    # 创建bridge
    createBridge $bridge_id
    if [[ $? -ne 0 ]]; then
        echo "Failed to create bridge"
        return 1
    fi
    # 将两个通道加入桥接
    add_channel_to_bridge "$channel2" "$bridge_id"
    if [[ $? -ne 0 ]]; then
        echo "$callee is busy"
        curl -s -X DELETE "$base_url/channels/$channel2" --data-urlencode "api_key=$api_key"
        curl -s -X DELETE "$base_url/channels/$channel1" --data-urlencode "api_key=$api_key"
        return 1
    fi
    answerChannel $channel1
    add_channel_to_bridge "$channel1" "$bridge_id"
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    # 开始录音
    record $bridge_id
    # 播放一段示例语音
    play $bridge_id
}

function createAndBridgeChannels() {
    createChannel $user1 $channel1_id
    if [[ $? -ne 0 ]]; then
        echo "Failed to create channel 1"
        return 1
    fi

    createChannel $user2 $channel2_id
    if [[ $? -ne 0 ]]; then
        echo "Failed to create channel 2"
        return 1
    fi

    # 创建bridge
    createBridge $bridge_id
    if [[ $? -ne 0 ]]; then
        echo "Failed to create bridge"
        return 1
    fi

    # 将两个通道加入桥接
    add_channel_to_bridge "$channel1_id" "$bridge_id"
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    add_channel_to_bridge "$channel2_id" "$bridge_id"
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    echo "Successfully created and bridged channels, bridgeId($bridge_id)"
}

# connect to websocket
function connect() {
    wscat -c "ws://$default_ip:8088/ari/events?api_key=$api_key&app=$app&subscribeAll=true"
}

function filterEvent() {
    local filterBody=$(jq -n '{
        allowed: [
            { type: "StasisStart" },
            { type: "StasisEnd" }
        ]
    }')
    echo $filterBody
    local filter_response=$(curl -s -X PUT "$base_url/applications/$app/eventFilter?api_key=$api_key" -H "Content-Type: application/json" -d "$filterBody")
    if [[ $? -ne 0 ]]; then
        echo "Failed to filter events"
        return 1
    fi

    echo "Successfully filter events"
}

# parse and call functions
IFS=',' read -ra cmds <<< "$commands"
for command in "${cmds[@]}"; do
    if declare -F "$command" > /dev/null; then
        $command
    fi
done

set +x
