#!/bin/bash
# HomePod Spotify Connect Setup Script
# For Raspberry Pi OS (Debian Trixie/Bookworm)
# This sets up a native Spotify Connect -> AirPlay bridge

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SPOTIFY_USER="${SPOTIFY_USER:-}"
SPOTIFY_PASS="${SPOTIFY_PASS:-}"
DEVICE_NAME="${DEVICE_NAME:-HomePod Spotify}"
PIPE_PATH="/srv/music/spotify"
OWNTONE_CONFIG_DIR="/etc/owntone"
OWNTONE_CACHE_DIR="/var/cache/owntone"
OWNTONE_USER="owntone"
OWNTONE_GROUP="audio"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_system() {
    log_info "Checking system compatibility..."
    
    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "arm"* && "$ARCH" != "aarch64" ]]; then
        log_warn "This doesn't appear to be a Raspberry Pi (Architecture: $ARCH)"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Detect Debian version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        log_info "Detected OS: $PRETTY_NAME"
        
        if [[ "$VERSION_CODENAME" == "bookworm" || "$VERSION_CODENAME" == "trixie" ]]; then
            log_info "Debian $VERSION_CODENAME detected - fully supported"
        elif [[ "$VERSION_ID" =~ ^12 ]]; then
            log_info "Debian 12 (Bookworm) detected - fully supported"
        else
            log_warn "Untested OS version. This script is designed for Debian Bookworm/Trixie"
        fi
    fi
}

install_dependencies() {
    log_info "Installing dependencies..."
    
    apt-get update
    
    # Essential build tools and libraries
    apt-get install -y \
        build-essential \
        git \
        cmake \
        autoconf \
        automake \
        libtool \
        pkg-config \
        libssl-dev \
        libasound2-dev \
        libpulse-dev \
        libavahi-client-dev \
        libcurl4-openssl-dev \
        libplist-dev \
        libsodium-dev \
        libjson-c-dev \
        libgcrypt20-dev \
        libavcodec-dev \
        libavformat-dev \
        libavutil-dev \
        libavfilter-dev \
        libswscale-dev \
        libevent-dev \
        libunistring-dev \
        libgpg-error-dev \
        libprotobuf-c-dev \
        libsqlite3-dev \
        libwebsockets-dev \
        libgnutls28-dev \
        alsa-utils \
        curl \
        wget
    
    # Rust toolchain for librespot
    if ! command -v rustc &> /dev/null; then
        log_info "Installing Rust toolchain..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env" || source "/root/.cargo/env"
    fi
    
    log_success "Dependencies installed"
}

install_librespot() {
    log_info "Installing librespot (Spotify Connect daemon)..."
    
    # Add cargo to PATH for this session
    export PATH="$HOME/.cargo/bin:/root/.cargo/bin:$PATH"
    
    # Create temporary build directory
    BUILD_DIR=$(mktemp -d)
    cd "$BUILD_DIR"
    
    # Clone and build librespot with pipe backend
    git clone https://github.com/librespot-org/librespot.git
    cd librespot
    
    # Build with alsa-backend for pipe support
    cargo build --release --features "alsa-backend"
    
    # Install binary
    cp target/release/librespot /usr/local/bin/
    chmod +x /usr/local/bin/librespot
    
    # Create librespot user
    if ! id "librespot" &>/dev/null; then
        useradd -r -s /bin/false librespot
        usermod -aG audio librespot
    fi
    
    # Cleanup
    cd /
    rm -rf "$BUILD_DIR"
    
    log_success "librespot installed"
}

setup_pipe() {
    log_info "Setting up audio pipe at $PIPE_PATH..."
    
    # Create directory structure
    mkdir -p "$(dirname "$PIPE_PATH")"
    
    # Remove existing file/pipe if present
    if [[ -e "$PIPE_PATH" ]]; then
        rm -f "$PIPE_PATH"
    fi
    
    # Create the named pipe (FIFO)
    mkfifo "$PIPE_PATH"
    
    # Set ownership and permissions
    # Group audio needs access
    chown root:audio "$PIPE_PATH"
    chmod 0666 "$PIPE_PATH"
    
    log_success "Audio pipe created at $PIPE_PATH"
}

build_owntone() {
    log_info "Building OwnTone (forked-daapd) from source..."
    
    # Create temporary build directory
    BUILD_DIR=$(mktemp -d)
    cd "$BUILD_DIR"
    
    # Clone OwnTone
    git clone https://github.com/owntone/owntone-server.git
    cd owntone-server
    
    # Run autoreconf to generate configure script
    autoreconf -fi
    
    # Configure with necessary options
    # Enable all AirPlay features and pipe input
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --enable-chromecast \
        --enable-lastfm \
        --enable-spotify \
        --with-pulseaudio=no \
        --with-alsa=yes
    
    # Build
    make -j$(nproc)
    
    # Install
    make install
    
    # Create owntone user if it doesn't exist
    if ! id "$OWNTONE_USER" &>/dev/null; then
        useradd -r -s /bin/false -G audio "$OWNTONE_USER"
    fi
    
    # Create necessary directories
    mkdir -p "$OWNTONE_CONFIG_DIR"
    mkdir -p "$OWNTONE_CACHE_DIR"
    mkdir -p "/srv/music"
    
    # Set ownership
    chown -R "$OWNTONE_USER:$OWNTONE_GROUP" "$OWNTONE_CACHE_DIR"
    chown -R "$OWNTONE_USER:$OWNTONE_GROUP" "/srv/music"
    
    # Cleanup
    cd /
    rm -rf "$BUILD_DIR"
    
    log_success "OwnTone built and installed"
}

configure_owntone() {
    log_info "Configuring OwnTone..."
    
    # Create the main configuration file
    cat > "$OWNTONE_CONFIG_DIR/owntone.conf" << 'EOF'
# OwnTone configuration for HomePod Spotify Connect
# Generated by setup script

# General settings
general {
    # Daemon settings
    uid = "owntone"
    loglevel = log
    # Don't drop privileges (needed for pipe access)
    # drop_privileges = true
    
    # Database
    db_path = "/var/cache/owntone/songs3.db"
    db_backup_path = "/var/cache/owntone/songs3.bak"
    
    # Library paths
    # Use the pipe as our only audio source
    library {
        name = "Spotify Pipe"
        path = "/srv/music"
    }
    
    # File scan settings
    filescan_disable = false
    rescan_disable = false
    
    # Decoding
    decode {
        # Format for the pipe (44100 Hz, 16-bit, stereo)
        sample_rate = 44100
        bit_depth = 16
        channels = 2
    }
    
    # Websocket interface for remote control
    websocket_port = 3688
    
    # MP3 streaming (for web interface)
    # Streaming disabled - we only care about AirPlay output
    # streaming {
    #     enabled = no
    # }
}

# Library settings
library {
    # Name shown in AirPlay/Remote
    name = "HomePod Spotify"
    
    # Scan and cache settings
    cache_path = "/var/cache/owntone"
    
    # File types to index
    filetypes = "mp3,ogg,flac,wav,alac,opus"
    
    # Compilations
    compilations = false
}

# Audio output settings
audio {
    # Default audio output (will be set to HomePod via web UI)
    # AirPlay volume (0-100)
    volume = 100
    
    # Audio quality
    # AirPlay 1 uses ALAC, AirPlay 2 uses AAC
    # We let OwnTone handle transcoding
    
    # Buffer settings
    # Increase buffer for stability with pipe input
    buffer_start_before_fill = 10
}

# AirPlay settings
airplay {
    # Device name shown in AirPlay menus
    name = "HomePod Spotify"
    
    # AirPlay 2 support
    # Set to true for AirPlay 2, false for AirPlay 1 only
    # HomePod supports both
    raop_disable = false
    airplay2 = true
    
    # Password protection (optional)
    # password = ""
    
    # Permitted remote control (from Apple Remote app)
    # 0 = disable, 1 = from localhost only, 2 = from any host
    control_port = 0
    
    # Timing port
    timing_port = 0
    
    # Require password for pairing
    require_password = false
}

# Chromecast settings (disabled for this setup)
chromecast {
    enabled = false
}

# Spotify integration (disabled - we use librespot)
spotify {
    enabled = false
}

# Last.fm (optional)
lastfm {
    enabled = false
}

# Pipe input for librespot
# This tells OwnTone to read from our named pipe
pipe {
    enabled = true
    # The named pipe path
    path = "/srv/music/spotify"
    # Format: pcm_s16le (signed 16-bit little-endian PCM)
    format = "pcm_s16le"
    # Sample rate must match librespot output
    sample_rate = 44100
    # Stereo channels
    channels = 2
}

# Web interface
# Accessible on port 3689
webinterface {
    enabled = true
    port = 3689
    # Bind to all interfaces
    bind_address = "0.0.0.0"
    # Document root (built-in)
    # docroot = "/usr/share/owntone/htdocs"
}
EOF

    # Set ownership
    chown "$OWNTONE_USER:$OWNTONE_GROUP" "$OWNTONE_CONFIG_DIR/owntone.conf"
    chmod 644 "$OWNTONE_CONFIG_DIR/owntone.conf"
    
    log_success "OwnTone configured"
}

configure_librespot() {
    log_info "Configuring librespot..."
    
    # Create configuration directory
    mkdir -p /etc/librespot
    
    # Get device name
    read -p "Enter the name for your Spotify Connect device [HomePod Spotify]: " DEVICE_NAME_INPUT
    DEVICE_NAME="${DEVICE_NAME_INPUT:-$DEVICE_NAME}"
    
    # Ask for credentials (optional)
    echo ""
    echo "Spotify Premium credentials (optional - leave blank for discovery mode):"
    read -p "Spotify Username (email): " SPOTIFY_USER
    if [[ -n "$SPOTIFY_USER" ]]; then
        read -s -p "Spotify Password: " SPOTIFY_PASS
        echo
    fi
    
    # Create the service configuration
    cat > /etc/librespot/librespot.conf << EOF
# Librespot configuration for HomePod Spotify Connect
DEVICE_NAME="$DEVICE_NAME"
BACKEND="pipe"
DEVICE="$PIPE_PATH"
BITRATE="320"
CACHE="/var/cache/librespot"
CACHE_SIZE_LIMIT="1G"
INITIAL_VOLUME="100"
EOF

    if [[ -n "$SPOTIFY_USER" ]]; then
        echo "USERNAME=\"$SPOTIFY_USER\"" >> /etc/librespot/librespot.conf
        echo "PASSWORD=\"$SPOTIFY_PASS\"" >> /etc/librespot/librespot.conf
    fi
    
    # Create cache directory
    mkdir -p /var/cache/librespot
    chown -R librespot:librespot /var/cache/librespot
    
    log_success "librespot configured"
}

create_librespot_service() {
    log_info "Creating librespot systemd service..."
    
    cat > /etc/systemd/system/librespot.service << 'EOF'
[Unit]
Description=Librespot (Spotify Connect)
Documentation=https://github.com/librespot-org/librespot
After=network.target sound.target
Wants=network.target

[Service]
Type=simple
User=librespot
Group=audio

# Load configuration
EnvironmentFile=/etc/librespot/librespot.conf

# Create the pipe if it doesn't exist, ensure permissions
ExecStartPre=/bin/bash -c 'mkdir -p /srv/music && rm -f /srv/music/spotify && mkfifo /srv/music/spotify && chmod 0666 /srv/music/spotify && chown root:audio /srv/music/spotify'

# Main command
# Using pipe backend to output to named pipe
ExecStart=/usr/local/bin/librespot \
    --name "${DEVICE_NAME}" \
    --backend pipe \
    --device /srv/music/spotify \
    --bitrate ${BITRATE:-320} \
    --cache /var/cache/librespot \
    --cache-size-limit ${CACHE_SIZE_LIMIT:-1G} \
    --initial-volume ${INITIAL_VOLUME:-100} \
    --enable-volume-normalisation \
    --normalisation-pregain 0 \
    $([ -n "${USERNAME:-}" ] && echo "--username ${USERNAME}") \
    $([ -n "${PASSWORD:-}" ] && echo "--password ${PASSWORD}")

# Restart on failure
Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/cache/librespot /srv/music

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    
    log_success "librespot service created"
}

create_owntone_service() {
    log_info "Creating OwnTone systemd service..."
    
    cat > /etc/systemd/system/owntone.service << 'EOF'
[Unit]
Description=OwnTone (forked-daapd) - DAAP/DACP/iTunes, AirPlay and Spotify server
Documentation=https://github.com/owntone/owntone-server
After=network.target sound.target
Wants=network.target

[Service]
Type=simple
User=owntone
Group=audio

# Ensure pipe exists and has correct permissions
ExecStartPre=/bin/bash -c 'mkdir -p /srv/music && chmod 755 /srv/music && if [ ! -p /srv/music/spotify ]; then rm -f /srv/music/spotify; mkfifo /srv/music/spotify; chmod 0666 /srv/music/spotify; chown root:audio /srv/music/spotify; fi'

# Wait a moment for librespot to start and open the pipe
ExecStartPre=/bin/sleep 2

# Main command
ExecStart=/usr/sbin/owntone -f -c /etc/owntone/owntone.conf

# Restart on failure
Restart=always
RestartSec=10

# Security settings
NoNewPrivileges=false
ProtectSystem=false
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    
    log_success "OwnTone service created"
}

start_services() {
    log_info "Starting services..."
    
    # Enable services to start on boot
    systemctl enable librespot.service
    systemctl enable owntone.service
    
    # Start librespot first (it creates/opens the pipe)
    systemctl start librespot.service
    sleep 3
    
    # Start owntone
    systemctl start owntone.service
    sleep 2
    
    # Check status
    log_info "Checking service status..."
    
    if systemctl is-active --quiet librespot; then
        log_success "librespot is running"
    else
        log_error "librespot failed to start"
        systemctl status librespot --no-pager
    fi
    
    if systemctl is-active --quiet owntone; then
        log_success "owntone is running"
    else
        log_error "owntone failed to start"
        systemctl status owntone --no-pager
    fi
}

show_completion() {
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo "=========================================="
    log_success "Setup Complete!"
    echo "=========================================="
    echo ""
    echo "Your HomePod Spotify Connect bridge is now installed."
    echo ""
    echo "Spotify Connect Device: $DEVICE_NAME"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. Configure HomePod Output:"
    echo "   Open http://$IP_ADDRESS:3689 in your browser"
    echo "   Go to Settings → Outputs"
    echo "   Select your HomePod from the available AirPlay devices"
    echo "   Enable it as the default output"
    echo ""
    echo "2. Connect from Spotify:"
    echo "   Open Spotify on your phone/computer"
    echo "   Look for '$DEVICE_NAME' in Spotify Connect devices"
    echo "   Select it and start playing!"
    echo ""
    echo "Service Management:"
    echo "   sudo systemctl status librespot  - Check Spotify Connect status"
    echo "   sudo systemctl status owntone    - Check OwnTone status"
    echo "   sudo systemctl restart librespot - Restart Spotify Connect"
    echo "   sudo systemctl restart owntone   - Restart OwnTone"
    echo ""
    echo "Logs:"
    echo "   sudo journalctl -u librespot -f  - Watch librespot logs"
    echo "   sudo journalctl -u owntone -f    - Watch OwnTone logs"
    echo ""
    echo "Troubleshooting:"
    echo "   - Make sure your HomePod allows AirPlay from 'Anyone on the same network'"
    echo "     (Home app → HomePod → Settings → AirPlay & Handoff)"
    echo "   - Both Pi and your phone must be on the same WiFi network"
    echo "   - If no audio, check that the pipe exists: ls -la /srv/music/spotify"
    echo ""
    log_success "Enjoy your music on HomePod via Spotify Connect!"
    echo ""
}

main() {
    echo ""
    echo "🎵 HomePod Spotify Connect Setup"
    echo "================================="
    echo ""
    echo "This script will install:"
    echo "  • librespot - Spotify Connect receiver"
    echo "  • OwnTone - AirPlay server (built from source)"
    echo "  • Systemd services for auto-start"
    echo ""
    read -p "Continue with installation? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    check_root
    check_system
    install_dependencies
    setup_pipe
    install_librespot
    build_owntone
    configure_owntone
    configure_librespot
    create_librespot_service
    create_owntone_service
    start_services
    show_completion
}

# Run main function
main
