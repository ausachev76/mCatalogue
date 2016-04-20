#!/bin/bash

cd "$(dirname "$0")"

HOST_APP_REPO_NAME=ios_hostapp
HOST_APP_REPO_URL="https://github.com/ausachev76/$HOST_APP_REPO_NAME.git"
MAIN_SCRIPT="$HOST_APP_REPO_NAME/configure_module.sh"

if [ ! -x "$MAIN_SCRIPT" ]; then
    git clone "$HOST_APP_REPO_URL" "$HOST_APP_REPO_NAME"
fi

if [ -x "$MAIN_SCRIPT" ]; then
    "$MAIN_SCRIPT"
else
    echo "
A problem occured while running '$MAIN_SCRIPT'.
You may delete '$HOST_APP_REPO_NAME' folder and try again."
fi
