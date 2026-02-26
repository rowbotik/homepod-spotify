#!/bin/bash
set -e

echo "🎵 HomePod Spotify Connect Setup"
echo "================================"
echo ""

# Check if running on Raspberry Pi
if [[ $(uname -m) != "arm"* && $(uname -m) != "aarch64" ]]; then
    echo "⚠️  Warning: This doesn't appear to be a Raspberry Pi"
    echo "    Architecture: $(uname -m)"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "✅ Docker installed. You'll need to log out and back in, then re-run this script."
    exit 0
fi

# Install docker-compose if not present
if ! command -v docker-compose &> /dev/null; then
    echo "📦 Installing docker-compose..."
    sudo apt update
    sudo apt install -y docker-compose
fi

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p ~/homepod-spotify/{config, pipe}

# Create the named pipe (FIFO)
echo "🔧 Creating audio pipe..."
PIPE_PATH="$HOME/homepod-spotify/pipe/spotify_fifo"
if [[ ! -p "$PIPE_PATH" ]]; then
    mkfifo "$PIPE_PATH"
fi

# Set permissions
chmod 666 "$PIPE_PATH"

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit ~/homepod-spotify/.env to set your device name (optional)"
echo "2. Run: docker-compose up -d"
echo "3. Wait 30 seconds for services to start"
echo "4. Open http://$(hostname -I | awk '{print $1}'):3689 to configure HomePod output"
echo ""
echo "Your HomePod should appear as a Spotify Connect device shortly!"
