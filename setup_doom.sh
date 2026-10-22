#!/bin/bash
# Doom Setup Script

echo "Setting up Doom environment..."

# Check if chocolate-doom is installed
if ! command -v chocolate-doom &> /dev/null && [ ! -f /usr/games/chocolate-doom ]; then
    echo "Installing Chocolate Doom and Freedoom..."
    apt update
    apt install -y chocolate-doom freedoom
fi

# Create directories
mkdir -p ~/.local/share/games/doom
mkdir -p ~/doom

# Link WAD files if they exist
if [ -f /usr/share/games/doom/freedoom1.wad ] && [ ! -f ~/.local/share/games/doom/freedoom1.wad ]; then
    ln -sf /usr/share/games/doom/freedoom1.wad ~/.local/share/games/doom/
fi
if [ -f /usr/share/games/doom/freedoom2.wad ] && [ ! -f ~/.local/share/games/doom/freedoom2.wad ]; then
    ln -sf /usr/share/games/doom/freedoom2.wad ~/.local/share/games/doom/
fi

# Create launch script
cat > ~/doom/launch_doom.sh << 'DOOMEOF'
#!/bin/bash
# Launch Doom (Freedoom)

DOOMPORT="/usr/games/chocolate-doom"
IWAD="freedoom2.wad"

if [ "$1" == "1" ]; then
    IWAD="freedoom1.wad"
fi

# Use xvfb if no display available
if [ -z "$DISPLAY" ]; then
    if command -v xvfb-run &> /dev/null; then
        xvfb-run -a "$DOOMPORT" -iwad "$IWAD" "${@:2}"
    else
        echo "No display found and xvfb-run not available"
        exit 1
    fi
else
    "$DOOMPORT" -iwad "$IWAD" "${@:2}"
fi
DOOMEOF

chmod +x ~/doom/launch_doom.sh

echo "Doom setup complete!"
echo "Launch with: ~/doom/launch_doom.sh [1|2] [options]"
echo "Freedoom 1: ~/doom/launch_doom.sh 1"
echo "Freedoom 2: ~/doom/launch_doom.sh 2 (default)"
