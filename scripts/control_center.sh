#!/bin/bash

get_status() {
    # 1. Wifi Status
    wifi_status=$(nmcli radio wifi)
    if [ "$wifi_status" = "enabled" ]; then
        wifi_enabled=true
        # Get active SSID
        wifi_ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)
        if [ -z "$wifi_ssid" ]; then
            wifi_ssid="Connected"
        fi
    else
        wifi_enabled=false
        wifi_ssid="Disabled"
    fi

    # 2. Bluetooth Status
    bt_powered=$(bluetoothctl show | grep "Powered:" | awk '{print $2}')
    if [ "$bt_powered" = "yes" ]; then
        bt_enabled=true
    else
        bt_enabled=false
    fi

    # 3. Power profile
    current_profile=$(powerprofilesctl get)

    # Output JSON
    echo "{\"wifi\": $wifi_enabled, \"wifi_ssid\": \"$wifi_ssid\", \"bluetooth\": $bt_enabled, \"profile\": \"$current_profile\"}"
}

toggle_wifi() {
    status=$(nmcli radio wifi)
    if [ "$status" = "enabled" ]; then
        nmcli radio wifi off
    else
        nmcli radio wifi on
    fi
}

toggle_bluetooth() {
    bt_powered=$(bluetoothctl show | grep "Powered:" | awk '{print $2}')
    if [ "$bt_powered" = "yes" ]; then
        bluetoothctl power off
    else
        bluetoothctl power on
    fi
}

toggle_saver() {
    current=$(powerprofilesctl get)
    if [ "$current" = "power-saver" ]; then
        powerprofilesctl set balanced
    else
        powerprofilesctl set power-saver
    fi
}

cycle_performance() {
    current=$(powerprofilesctl get)
    if [ "$current" = "power-saver" ]; then
        powerprofilesctl set balanced
    elif [ "$current" = "balanced" ]; then
        powerprofilesctl set performance
    else
        powerprofilesctl set power-saver
    fi
}

get_wifi_list() {
    nmcli -t -f SSID,SIGNAL,SECURITY,ACTIVE dev wifi list --rescan yes 2>/dev/null | awk -F: '
    NF >= 4 && $1 != "" {
        ssid = $1
        sig = $2
        sec = $3
        act = $4
        if (!(ssid in signal) || sig > signal[ssid]) {
            signal[ssid] = sig
            security[ssid] = sec
            active[ssid] = act
        }
    }
    END {
        print "["
        first = 1
        for (ssid in signal) {
            clean_ssid = ssid
            gsub(/"/, "\\\"", clean_ssid)
            if (!first) print ","
            first = 0
            sec_type = "Open"
            if (security[ssid] != "") {
                sec_type = "Secured"
            }
            printf "{\"ssid\":\"%s\", \"signal\":%d, \"security\":\"%s\", \"active\":%s}", clean_ssid, signal[ssid], sec_type, (active[ssid] == "yes" ? "true" : "false")
        }
        print "]"
    }
    ' ORS=""
}

get_bt_list() {
    echo -n "["
    first=1
    bluetoothctl devices 2>/dev/null | while read -r line; do
        if [ -n "$line" ]; then
            mac=$(echo "$line" | awk '{print $2}')
            name=$(echo "$line" | cut -d' ' -f3-)
            
            # Check connection status
            connected=false
            if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
                connected=true
            fi
            
            clean_name=$name
            clean_name=${clean_name//\"/\\\"}
            
            if [ "$first" -ne 1 ]; then
                echo -n ","
            fi
            first=0
            
            printf "{\"mac\":\"%s\", \"name\":\"%s\", \"connected\":%s}" "$mac" "$clean_name" "$connected"
        fi
    done
    echo -n "]"
}

connect_wifi() {
    ssid="$1"
    password="$2"
    if [ -n "$password" ]; then
        nmcli dev wifi connect "$ssid" password "$password"
    else
        nmcli dev wifi connect "$ssid"
    fi
}

connect_bt() {
    mac="$1"
    # Check if already paired
    paired=$(bluetoothctl info "$mac" 2>/dev/null | grep "Paired:" | awk '{print $2}')
    if [ "$paired" != "yes" ]; then
        bluetoothctl pair "$mac"
        bluetoothctl trust "$mac"
    fi
    bluetoothctl connect "$mac"
}

disconnect_bt() {
    mac="$1"
    bluetoothctl disconnect "$mac"
}

case "$1" in
    get)
        get_status
        ;;
    toggle-wifi)
        toggle_wifi
        get_status
        ;;
    toggle-bluetooth)
        toggle_bluetooth
        get_status
        ;;
    toggle-saver)
        toggle_saver
        get_status
        ;;
    cycle-performance)
        cycle_performance
        get_status
        ;;
    get-wifi-list)
        get_wifi_list
        ;;
    get-bt-list)
        get_bt_list
        ;;
    connect-wifi)
        connect_wifi "$2" "$3"
        ;;
    connect-bt)
        connect_bt "$2"
        ;;
    disconnect-bt)
        disconnect_bt "$2"
        ;;
    *)
        echo "Usage: $0 {get|toggle-wifi|toggle-bluetooth|toggle-saver|cycle-performance|get-wifi-list|get-bt-list|connect-wifi|connect-bt|disconnect-bt}"
        exit 1
        ;;
esac
