#!/bin/bash
# Power cycle the AP630 via PoE on the SR2024 switch.
# Uses PSE shutdown/enable to cut and restore PoE power.
#
# Usage: power-cycle-ap.sh [delay_seconds]
#   default delay: 3 seconds

set -euo pipefail

SWITCH_IP="192.168.1.237"
SWITCH_USER="admin"
SWITCH_PW="aerohive"
PORT="eth1/4"
DELAY="${1:-3}"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"

expect -c "
set timeout 10
log_user 0
spawn ssh $SSH_OPTS $SWITCH_USER@$SWITCH_IP
expect \"assword:\"
send \"$SWITCH_PW\r\"
expect -re {AH-\[0-9a-f\]+#}
send \"interface $PORT pse shutdown\r\"
expect -re {AH-\[0-9a-f\]+#}
sleep $DELAY
send \"no interface $PORT pse shutdown\r\"
expect -re {AH-\[0-9a-f\]+#}
send \"exit\r\"
expect eof
" 2>&1

echo "PoE cycled on $PORT (${DELAY}s off)"
