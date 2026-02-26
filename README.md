# HomePod Spotify Connect 🎵

Turn your HomePod into a native Spotify Connect speaker using a Raspberry Pi.

## What This Does

- **Raspotify**: Creates a Spotify Connect receiver on your network
- **OwnTone**: Receives the audio and AirPlays it to your HomePod
- **Named Pipe**: Connects them so audio flows seamlessly

Result: Your HomePod appears as a Spotify Connect device in the Spotify app.

## Requirements

- Raspberry Pi 3 B+ (or newer)
- Raspberry Pi OS Lite (64-bit recommended)
- Spotify Premium account (required for Connect)
- HomePod on the same network

## Quick Start

### 1. Flash Your SD Card

Use Raspberry Pi Imager:
- Choose **Raspberry Pi OS Lite (64-bit)**
- Set hostname: `homepod-spotify` (optional)
- Enable SSH and set your WiFi credentials

### 2. Clone and Setup

```bash
# SSH into your Pi
ssh pi@homepod-spotify.local

# Clone this repo
git clone https://github.com/YOUR_USERNAME/homepod-spotify.git
cd homepod-spotify

# Run setup
chmod +x setup.sh
./setup.sh
```

### 3. Configure (Optional)

```bash
# Copy and edit the config
cp .env.example .env
nano .env
```

Change `DEVICE_NAME` if you want it to show up differently in Spotify.

### 4. Start It Up

```bash
docker-compose up -d
```

Wait about 30 seconds for everything to initialize.

### 5. Configure HomePod Output

1. Open `http://your-pi-ip:3689` in a browser
2. You should see the OwnTone web interface
3. Go to Settings → Outputs
4. Select your HomePod from the list
5. Enable it as the default output

### 6. Enjoy

Open Spotify on your phone/computer. Look for **"HomePod Spotify"** (or whatever you named it) in your Spotify Connect devices.

## How It Works

```
[Spotify App] → [Raspotify on Pi] → [Named Pipe] → [OwnTone] → [AirPlay] → [HomePod]
```

## Troubleshooting

### Can't see the Spotify Connect device?
- Make sure your phone and Pi are on the same network
- Check logs: `docker-compose logs raspotify`
- Try restarting: `docker-compose restart`

### HomePod not showing in OwnTone?
- Make sure HomePod has "AirPlay access" set to "Anyone on the same network"
  - Home app → HomePod → Settings → AirPlay & Handoff
- Check logs: `docker-compose logs owntone`
- Restart the HomePod

### Audio cuts out or stutters?
- Pi 3 B+ should handle this fine, but try lowering bitrate in `.env`:
  - `BITRATE=160` for more stability
- Check WiFi signal strength on the Pi

### Want to update?
```bash
cd ~/homepod-spotify
docker-compose pull
docker-compose up -d
```

## Uninstall

```bash
cd ~/homepod-spotify
docker-compose down -v
rm -rf ~/homepod-spotify
```

## Credits

- [Raspotify](https://github.com/dtcooper/raspotify) - Spotify Connect for Linux
- [OwnTone](https://github.com/owntone/owntone-server) - AirPlay server
- Original concept from [HomePod Connect](https://community.home-assistant.io/t/homepod-connect-spotify-on-homepods-with-spotify-connect/482227)

## License

MIT - Do whatever you want with this.
