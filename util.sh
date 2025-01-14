#!/bin/env bash

#set -x

base_url="http://192.168.6.5:8088/ari"
api_key="asterisk:passwd"
bridge_id=123
channel1_id=123
channel2_id=456

# clear all channels
clearChannels() {
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

clearBridges() {
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

createAndBridgeChannels() {
    local channel1_response
    channel1_response=$(curl -s -X POST "$base_url/channels?endpoint=PJSIP%2F6001&app=test&timeout=30&channelId=$channel1_id&api_key=$api_key")

    if [[ $? -ne 0 ]]; then
        echo "Failed to create channel 1"
        return 1
    fi

    local channel2_response
    channel2_response=$(curl -s -X POST "$base_url/channels?endpoint=PJSIP%2F6002&app=test&timeout=30&channelId=$channel2_id&api_key=$api_key")

    if [[ $? -ne 0 ]]; then
        echo "Failed to create channel 2"
        return 1
    fi

    # 创建bridge
    local bridge_response
    bridge_response=$(curl -s -X POST "$base_url/bridges/$bridge_id?api_key=$api_key")

    if [[ $? -ne 0 ]]; then
        echo "Failed to create bridge"
        return 1
    fi

    add_channel_to_bridge() {
        local channel_id=$1
        while true; do
            local channel_status_response
            channel_status_response=$(curl -s -G "$base_url/channels/$channel_id" --data-urlencode "api_key=$api_key")
            local state=$(echo "$channel_status_response" | jq -r '.state')
            if [[ "$state" == "Up" ]]; then
                break
            fi
            sleep 1
        done
        local add_channel_response
        add_channel_response=$(curl -s -X POST "$base_url/bridges/$bridge_id/addChannel?channel=$channel_id&api_key=$api_key")
        if [[ $? -ne 0 ]]; then
            echo "Failed to add channel $channel_id to bridge"
            return 1
        fi
        echo "Successfully add $channel_id to bridge"
    }
    # 将两个通道加入桥接
    add_channel_to_bridge "$channel1_id"
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    add_channel_to_bridge "$channel2_id"
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    echo "Successfully created and bridged channels, bridgeId($bridge_id)"
}

clearChannels
clearBridges
createAndBridgeChannels

set +x
