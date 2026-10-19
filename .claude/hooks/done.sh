#!/bin/bash

# Check if we've already notified
if [ -f /tmp/already_notified ]; then
    rm /tmp/already_notified
    exit 0
fi

# Create the token file to indicate we're about to notify
touch /tmp/already_notified

# Send Ghostty notification
printf '\e]777;notify;Claude Code;Task completed\a'

exit 0
