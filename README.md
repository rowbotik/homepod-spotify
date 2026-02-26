# HomePod Spotify Connect 🎵

Turn your HomePod into a native Spotify Connect speaker using a Raspberry Pi.

## What This Does

- **librespot**: Creates a Spotify Connect receiver on your network with pipe output
- **OwnTone**: Receives the audio via named pipe and AirPlays it to your HomePod
- **Named Pipe**: Connects them so audio flows seamlessly at `/srv/music/spotify`

Result: Your HomePod appears as a Spotify Connect device in the Spotify app.

## Requirements

- Raspberry Pi 3 B+ or newer (Pi 4 recommended)
- Raspberry Pi OS Lite (64-bit, Bookworm or Trixie)
- Spotify Premium account (required for Connect)
- HomePod on the same network
- At least 2GB free disk space (for building OwnTone from source)

## Quick Start

### 1. Flash Your SD Card

Use Raspberry Pi Imager:
- Choose **Raspberry Pi OS Lite (64-bit)** - Debian Bookworm or Trixie
- Set hostname: `homepod-spotify` (optional)
- Enable SSH and set your WiFi credentials

### 2. SSH and Run Setup

```bash
# SSH into your Pi
ssh pi@homepod-spotify.local

# Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/rowbotik/homepod-spotify/main/setup.sh -o setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

Or clone the repo:

```bash
# Clone this repo
git clone https://github.com/rowbotik/homepod-spotify.git
cd homepod-spotify

# Run setup (must be root)
sudo ./setup.sh
```

The script will:
1. Install all dependencies
2. Build OwnTone from source
3. Install librespot (Spotify Connect)
4. Create the named pipe at `/srv/music/spotify`
5. Configure and start both services
6. Prompt you for your Spotify device name

### 3. Configure HomePod Output

1. Open `http://your-pi-ip:3689` in a browser
2. You should see the OwnTone web interface
3. Go to **Settings → Outputs**
4. Select your HomePod from the list
5. Enable it as the default output

### 4. Connect from Spotify

1. Open Spotify on your phone/computer
2. Look for your device name (default: "HomePod Spotify") in the Spotify Connect menu
3. Select it and start playing!

## How It Works

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────┐     ┌──────────┐
│  Spotify App    │────▶│  librespot (Pi)  │────▶│  Named Pipe  │────▶│ OwnTone  │
│  (Phone/PC)     │     │  Spotify Connect │     │ /srv/music/  │     │ AirPlay  │
└─────────────────┘     └──────────────────┘     │   spotify    │     └────┬─────┘
                                                  └──────────────┘          │
                                                                            ▼
                                                                      ┌──────────┐
                                                                      │ HomePod  │
                                                                      └──────────┘
```

Audio flows: Spotify → librespot → named pipe → OwnTone → AirPlay → HomePod

## Service Management

```bash
# Check status
sudo systemctl status librespot
sudo systemctl status owntone

# Restart services
sudo systemctl restart librespot
sudo systemctl restart owntone

# View logs
sudo journalctl -u librespot -f
sudo journalctl -u owntone -f

# Enable/disable auto-start
sudo systemctl enable librespot
sudo systemctl enable owntone
```

## Configuration Files

- `/etc/librespot/librespot.conf` - Spotify device name and credentials
- `/etc/owntone/owntone.conf` - OwnTone (AirPlay server) configuration
- `/srv/music/spotify` - The named pipe for audio transfer

## Troubleshooting

### Services won't start?

Check the logs:
```bash
sudo journalctl -u librespot --no-pager
sudo journalctl -u owntone --no-pager
```

### Can't see the Spotify Connect device?

- Make sure your phone and Pi are on the same network
- Check librespot is running: `sudo systemctl status librespot`
- Check logs: `sudo journalctl -u librespot -f`
- Try restarting: `sudo systemctl restart librespot`
- Ensure Spotify Premium (required for Connect)

### HomePod not showing in OwnTone?

- Make sure HomePod has "AirPlay access" set to "Anyone on the same network"
  - Home app → HomePod → Settings → AirPlay & Handoff
- Check OwnTone logs: `sudo journalctl -u owntone -f`
- Restart the HomePod
- Ensure Pi and HomePod are on the same WiFi network

### No audio playing?

- Check the pipe exists: `ls -la /srv/music/spotify`
- Pipe should show as `prw-rw-rw-` (named pipe with read/write permissions)
- Check both services are running: `sudo systemctl status librespot owntone`
- Ensure HomePod is selected as output in OwnTone web UI (port 3689)

### Audio cuts out or stutters?

- Check WiFi signal strength on the Pi: `iwconfig` or `iw dev wlan0 link`
- Lower the bitrate in `/etc/librespot/librespot.conf`:
  - `BITRATE="160"` for more stability
- Pi 3 B+ should handle 320kbps fine, but Pi 4 is more reliable

### Build fails on OwnTone?

- Ensure you have at least 2GB free space: `df -h`
- Make sure all dependencies installed correctly
- Try running the build steps manually to see errors

## Updating

### Update librespot:
```bash
# Re-run the install portion of setup
sudo bash -c '
  export PATH="$HOME/.cargo/bin:/root/.cargo/bin:$PATH"
  cd /tmp
  git clone https://github.com/librespot-org/librespot.git
  cd librespot
  cargo build --release --features "alsa-backend"
  cp target/release/librespot /usr/local/bin/
  systemctl restart librespot
'
```

### Update OwnTone:
```bash
# Re-run the build portion of setup
sudo bash -c '
  cd /tmp
  git clone https://github.com/owntone/owntone-server.git
  cd owntone-server
  autoreconf -fi
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-chromecast --enable-airplay2
  make -j$(nproc)
  make install
  systemctl restart owntone
'
```

## Uninstall

```bash
# Stop and disable services
sudo systemctl stop librespot owntone
sudo systemctl disable librespot owntone

# Remove systemd services
sudo rm -f /etc/systemd/system/librespot.service
sudo rm -f /etc/systemd/system/owntone.service
sudo systemctl daemon-reload

# Remove binaries
sudo rm -f /usr/local/bin/librespot
sudo rm -f /usr/sbin/owntone

# Remove configuration
sudo rm -rf /etc/librespot
sudo rm -rf /etc/owntone

# Remove cache
sudo rm -rf /var/cache/librespot
sudo rm -rf /var/cache/owntone

# Remove pipe
sudo rm -rf /srv/music

# Remove users (optional)
sudo userdel librespot 2>/dev/null || true
sudo userdel owntone 2>/dev/null || true

echo "Uninstalled successfully"
```

## Technical Details

### Architecture

This setup uses a **native installation** (not Docker) for:
- Lower overhead and better performance on Raspberry Pi
- Direct access to audio subsystem
- Native systemd integration
- Smaller resource footprint

### Pipe Format

The named pipe transfers raw PCM audio:
- Sample rate: 44100 Hz
- Bit depth: 16-bit signed little-endian
- Channels: Stereo (2)
- Format: `pcm_s16le`

### Security

- Services run as unprivileged users (`librespot` and `owntone`)
- Only members of the `audio` group can access the sound system
- Services are sandboxed with systemd security features
- Optional: Set AirPlay password in OwnTone config

## Credits

- [librespot](https://github.com/librespot-org/librespot) - Open source Spotify client library
- [OwnTone](https://github.com/owntone/owntone-server) - DAAP/DACP (iTunes), RSP (Roku) and AirPlay server
- Original concept from [HomePod Connect](https://community.home-assistant.io/t/homepod-connect-spotify-on-homepods-with-spotify-connect/482227)

## License

MIT - Do whatever you want with this.
