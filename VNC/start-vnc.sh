#!/bin/bash

# Set display resolution (change as needed)
export DISPLAY=:1

# Kill any existing VNC server instances
vncserver -kill :1 || true

# Start the VNC server
echo "Starting VNC server at $RESOLUTION..."
vncserver -geometry $RESOLUTION -depth 24 :1

# Launch Firefox in non-headless mode
echo "Starting Firefox in non-headless mode..."
firefox &

# Keep the container running
tail -f /dev/null
