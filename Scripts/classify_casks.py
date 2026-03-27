#!/usr/bin/env python3
"""
CaskHub Cask Classifier
Generates categories.json by classifying Homebrew casks into 15 categories.

Usage:
    python3 Scripts/classify_casks.py

Output:
    CaskHub/Resources/categories.json
"""

import json
import urllib.request
import os
import re
from datetime import date

# ─────────────────────────────────────────────────
# Category Definitions
# ─────────────────────────────────────────────────

CATEGORIES = [
    "developerTools",
    "browsers",
    "communication",
    "productivity",
    "utilities",
    "designGraphics",
    "audioMusic",
    "videoMedia",
    "games",
    "securityPrivacy",
    "financeCrypto",
    "cloudStorage",
    "scienceEducation",
    "menuBar",
    "other",
]

# ─────────────────────────────────────────────────
# Manual Overrides (highest priority, most accurate)
# ~300 popular apps hand-classified
# ─────────────────────────────────────────────────

MANUAL_OVERRIDES = {
    # Developer Tools
    "visual-studio-code": "developerTools",
    "cursor": "developerTools",
    "zed": "developerTools",
    "sublime-text": "developerTools",
    "nova": "developerTools",
    "bbedit": "developerTools",
    "textmate": "developerTools",
    "coteditor": "developerTools",
    "docker": "developerTools",
    "orbstack": "developerTools",
    "github-desktop": "developerTools",
    "gitkraken": "developerTools",
    "sourcetree": "developerTools",
    "tower": "developerTools",
    "fork": "developerTools",
    "postman": "developerTools",
    "insomnia": "developerTools",
    "paw": "developerTools",
    "rapidapi": "developerTools",
    "httpie": "developerTools",
    "proxyman": "developerTools",
    "charles": "developerTools",
    "tableplus": "developerTools",
    "sequel-pro": "developerTools",
    "dbeaver-community": "developerTools",
    "datagrip": "developerTools",
    "pgadmin4": "developerTools",
    "mongodb-compass": "developerTools",
    "redis-insight": "developerTools",
    "cyberduck": "developerTools",
    "transmit": "developerTools",
    "filezilla": "developerTools",
    "iterm2": "developerTools",
    "warp": "developerTools",
    "kitty": "developerTools",
    "alacritty": "developerTools",
    "ghostty": "developerTools",
    "hyper": "developerTools",
    "tabby": "developerTools",
    "rio": "developerTools",
    "wezterm": "developerTools",
    "intellij-idea": "developerTools",
    "intellij-idea-ce": "developerTools",
    "webstorm": "developerTools",
    "pycharm": "developerTools",
    "pycharm-ce": "developerTools",
    "phpstorm": "developerTools",
    "rubymine": "developerTools",
    "goland": "developerTools",
    "clion": "developerTools",
    "rider": "developerTools",
    "appcode": "developerTools",
    "android-studio": "developerTools",
    "fleet": "developerTools",
    "eclipse-ide": "developerTools",
    "eclipse-java": "developerTools",
    "netbeans": "developerTools",
    "xcodes": "developerTools",
    "sf-symbols": "developerTools",
    "dash": "developerTools",
    "kaleidoscope": "developerTools",
    "beyond-compare": "developerTools",
    "kdiff3": "developerTools",
    "meld": "developerTools",
    "diffmerge": "developerTools",
    "vagrant": "developerTools",
    "multipass": "developerTools",
    "cocoapods": "developerTools",
    "swiftformat-for-xcode": "developerTools",
    "swiftlint": "developerTools",
    "reveal": "developerTools",
    "figma": "designGraphics",
    "notion": "productivity",
    "raycast": "productivity",

    # Browsers
    "firefox": "browsers",
    "google-chrome": "browsers",
    "brave-browser": "browsers",
    "arc": "browsers",
    "microsoft-edge": "browsers",
    "opera": "browsers",
    "opera-gx": "browsers",
    "vivaldi": "browsers",
    "tor-browser": "browsers",
    "chromium": "browsers",
    "orion": "browsers",
    "zen-browser": "browsers",
    "min": "browsers",
    "sigmaos": "browsers",
    "waterfox": "browsers",
    "librewolf": "browsers",
    "mullvad-browser": "browsers",
    "floorp": "browsers",
    "ladybird": "browsers",

    # Communication
    "discord": "communication",
    "slack": "communication",
    "telegram": "communication",
    "telegram-desktop": "communication",
    "whatsapp": "communication",
    "signal": "communication",
    "zoom": "communication",
    "microsoft-teams": "communication",
    "skype": "communication",
    "webex": "communication",
    "element": "communication",
    "mattermost": "communication",
    "rocket-chat": "communication",
    "zulip": "communication",
    "mumble": "communication",
    "teamspeak-client": "communication",
    "lark": "communication",
    "dingtalk": "communication",
    "wechat": "communication",
    "line": "communication",
    "viber": "communication",
    "session": "communication",
    "beeper": "communication",
    "thunderbird": "communication",
    "spark": "communication",
    "airmail": "communication",
    "canary-mail": "communication",
    "hey": "communication",
    "mimestream": "communication",
    "readdle-spark": "communication",
    "postbox": "communication",
    "mailmate": "communication",
    "tutanota": "communication",

    # Productivity
    "obsidian": "productivity",
    "craft": "productivity",
    "bear": "productivity",
    "things": "productivity",
    "todoist": "productivity",
    "omnifocus": "productivity",
    "ticktick": "productivity",
    "fantastical": "productivity",
    "busycal": "productivity",
    "cardhop": "productivity",
    "busycontacts": "productivity",
    "microsoft-word": "productivity",
    "microsoft-excel": "productivity",
    "microsoft-powerpoint": "productivity",
    "microsoft-outlook": "productivity",
    "libreoffice": "productivity",
    "onlyoffice": "productivity",
    "openoffice": "productivity",
    "pdf-expert": "productivity",
    "devonthink": "productivity",
    "evernote": "productivity",
    "onenote": "productivity",
    "agenda": "productivity",
    "logseq": "productivity",
    "joplin": "productivity",
    "standard-notes": "productivity",
    "simplenote": "productivity",
    "typora": "productivity",
    "ia-writer": "productivity",
    "ulysses": "productivity",
    "scrivener": "productivity",
    "marked": "productivity",
    "macdown": "productivity",
    "grammarly-desktop": "productivity",
    "languagetool": "productivity",
    "deepl": "productivity",
    "popclip": "productivity",
    "paste": "productivity",
    "pastebot": "productivity",
    "keyboard-maestro": "productivity",
    "textexpander": "productivity",
    "typinator": "productivity",
    "hazel": "productivity",
    "hookmark": "productivity",
    "mindnode": "productivity",
    "xmind": "productivity",
    "freeplane": "productivity",
    "omnigraffle": "productivity",
    "omniplan": "productivity",
    "omnioutliner": "productivity",
    "airtable": "productivity",
    "coda": "productivity",
    "basecamp": "productivity",
    "asana": "productivity",
    "clickup": "productivity",
    "linear-linear": "productivity",
    "height": "productivity",
    "capacitor": "productivity",
    "numi": "productivity",
    "soulver": "productivity",
    "mela": "productivity",
    "anytype": "productivity",
    "apple-configurator": "productivity",
    "microsoft-auto-update": "productivity",

    # Utilities
    "alfred": "utilities",
    "rectangle": "utilities",
    "rectangle-pro": "utilities",
    "appcleaner": "utilities",
    "the-unarchiver": "utilities",
    "keka": "utilities",
    "betterzip": "utilities",
    "cleanmymac": "utilities",
    "onyx": "utilities",
    "daisydisk": "utilities",
    "grandperspective": "utilities",
    "disk-drill": "utilities",
    "balenaetcher": "utilities",
    "suspicious-package": "utilities",
    "apparency": "utilities",
    "pearcleaner": "utilities",
    "sensei": "utilities",
    "monitorcontrol": "utilities",
    "coconutbattery": "utilities",
    "amphetamine": "utilities",
    "caffeine": "utilities",
    "keepingyouawake": "utilities",
    "karabiner-elements": "utilities",
    "bettertouchtool": "utilities",
    "magnet": "utilities",
    "spectacle": "utilities",
    "hammerspoon": "utilities",
    "cheatsheet": "utilities",
    "shottr": "utilities",
    "cleanshot": "utilities",
    "snagit": "utilities",
    "handbrake": "utilities",
    "localsend": "utilities",
    "alt-tab": "utilities",
    "maccy": "utilities",
    "flycut": "utilities",
    "copyq": "utilities",
    "flux": "utilities",
    "numi": "utilities",
    "appshelf": "utilities",
    "brew-services-menubar": "utilities",
    "homebrew-cask": "utilities",
    "cakebrew": "utilities",
    "android-file-transfer": "utilities",
    "openinterminal": "utilities",
    "easy-move-plus-resize": "utilities",
    "hot": "utilities",
    "latest": "utilities",
    "suspicious-package": "utilities",
    "topnotch": "utilities",
    "swift-quit": "utilities",
    "logi-options-plus": "utilities",
    "logitech-g-hub": "utilities",
    "scroll-reverser": "utilities",
    "mos": "utilities",
    "linearmouse": "utilities",
    "mac-mouse-fix": "utilities",
    "raycast": "productivity",

    # Design & Graphics
    "sketch": "designGraphics",
    "adobe-creative-cloud": "designGraphics",
    "affinity-designer": "designGraphics",
    "affinity-designer-2": "designGraphics",
    "affinity-photo": "designGraphics",
    "affinity-photo-2": "designGraphics",
    "affinity-publisher": "designGraphics",
    "affinity-publisher-2": "designGraphics",
    "pixelmator-pro": "designGraphics",
    "gimp": "designGraphics",
    "inkscape": "designGraphics",
    "blender": "designGraphics",
    "zeplin": "designGraphics",
    "abstract": "designGraphics",
    "principle": "designGraphics",
    "flinto": "designGraphics",
    "lunacy": "designGraphics",
    "canva": "designGraphics",
    "colorsnapper": "designGraphics",
    "sip": "designGraphics",
    "iconjar": "designGraphics",
    "nucleo": "designGraphics",
    "fontexplorer-x-pro": "designGraphics",
    "rightfont": "designGraphics",
    "fontbase": "designGraphics",
    "iconchamp": "designGraphics",
    "image2icon": "designGraphics",
    "optimage": "designGraphics",
    "imageoptim": "designGraphics",
    "squash": "designGraphics",
    "acorn": "designGraphics",
    "paintbrush": "designGraphics",
    "krita": "designGraphics",
    "darktable": "designGraphics",
    "rawtherapee": "designGraphics",
    "capture-one": "designGraphics",
    "lightroom": "designGraphics",
    "photobooth": "designGraphics",
    "sketchup": "designGraphics",
    "cinema-4d": "designGraphics",
    "adobe-photoshop": "designGraphics",
    "adobe-illustrator": "designGraphics",
    "adobe-xd": "designGraphics",
    "adobe-indesign": "designGraphics",
    "adobe-lightroom": "designGraphics",
    "adobe-premiere-pro": "videoMedia",
    "adobe-after-effects": "videoMedia",
    "framer": "designGraphics",
    "penpot": "designGraphics",
    "origami-studio": "designGraphics",
    "protopie": "designGraphics",

    # Audio & Music
    "spotify": "audioMusic",
    "audacity": "audioMusic",
    "audio-hijack": "audioMusic",
    "soundsource": "audioMusic",
    "loopback": "audioMusic",
    "krisp": "audioMusic",
    "musescore": "audioMusic",
    "lmms": "audioMusic",
    "reaper": "audioMusic",
    "foobar2000": "audioMusic",
    "vox": "audioMusic",
    "swinsian": "audioMusic",
    "tidal": "audioMusic",
    "amazon-music": "audioMusic",
    "apple-music": "audioMusic",
    "deezer": "audioMusic",
    "splice": "audioMusic",
    "ableton-live-suite": "audioMusic",
    "ableton-live-lite": "audioMusic",
    "native-access": "audioMusic",
    "focusrite-control": "audioMusic",
    "blackhole-2ch": "audioMusic",
    "blackhole-16ch": "audioMusic",
    "background-music": "audioMusic",
    "sonic-visualiser": "audioMusic",
    "spek": "audioMusic",
    "xld": "audioMusic",

    # Video & Media
    "vlc": "videoMedia",
    "iina": "videoMedia",
    "mpv": "videoMedia",
    "plex": "videoMedia",
    "obs": "videoMedia",
    "screenflow": "videoMedia",
    "loom": "videoMedia",
    "kodi": "videoMedia",
    "infuse": "videoMedia",
    "elmedia-player": "videoMedia",
    "movist-pro": "videoMedia",
    "movist": "videoMedia",
    "downie": "videoMedia",
    "permute": "videoMedia",
    "davinci-resolve": "videoMedia",
    "final-cut-pro": "videoMedia",
    "shotcut": "videoMedia",
    "kdenlive": "videoMedia",
    "openshot-video-editor": "videoMedia",
    "stremio": "videoMedia",
    "jellyfin-media-player": "videoMedia",
    "emby-server": "videoMedia",
    "clipgrab": "videoMedia",
    "4k-video-downloader": "videoMedia",
    "youtube-downloader": "videoMedia",
    "gifox": "videoMedia",
    "gifrocket": "videoMedia",
    "kap": "videoMedia",
    "licecap": "videoMedia",

    # Games
    "steam": "games",
    "epic-games": "games",
    "gog-galaxy": "games",
    "battle-net": "games",
    "minecraft": "games",
    "openemu": "games",
    "retroarch": "games",
    "itch": "games",
    "lunar-client": "games",
    "curseforge": "games",
    "overwolf": "games",
    "parsec": "games",
    "moonlight": "games",
    "nvidia-geforce-now": "games",
    "xbox": "games",
    "playstation-remote-play": "games",
    "ea-app": "games",
    "ubisoft-connect": "games",
    "prismlauncher": "games",
    "cemu": "games",
    "dolphin": "games",
    "ryujinx": "games",
    "ppsspp": "games",
    "mgba": "games",
    "dosbox-x": "games",
    "wine-stable": "games",
    "crossover": "games",
    "whisky": "games",
    "heroic": "games",
    "porting-kit": "games",
    "joystick-doctor": "games",
    "enjoyable": "games",
    "gametrack": "games",

    # Security & Privacy
    "1password": "securityPrivacy",
    "bitwarden": "securityPrivacy",
    "keepassxc": "securityPrivacy",
    "lastpass": "securityPrivacy",
    "dashlane": "securityPrivacy",
    "enpass": "securityPrivacy",
    "nordvpn": "securityPrivacy",
    "mullvad-vpn": "securityPrivacy",
    "protonvpn": "securityPrivacy",
    "expressvpn": "securityPrivacy",
    "surfshark": "securityPrivacy",
    "tunnelblick": "securityPrivacy",
    "cloudflare-warp": "securityPrivacy",
    "tailscale": "securityPrivacy",
    "wireguard-tools": "securityPrivacy",
    "openvpn-connect": "securityPrivacy",
    "viscosity": "securityPrivacy",
    "wireshark": "securityPrivacy",
    "little-snitch": "securityPrivacy",
    "lulu": "securityPrivacy",
    "micro-snitch": "securityPrivacy",
    "blockblock": "securityPrivacy",
    "oversight": "securityPrivacy",
    "gpg-suite": "securityPrivacy",
    "veracrypt": "securityPrivacy",
    "cryptomator": "securityPrivacy",
    "keybase": "securityPrivacy",
    "proton-mail": "securityPrivacy",
    "proton-drive": "securityPrivacy",
    "malwarebytes": "securityPrivacy",
    "objective-see-lulu": "securityPrivacy",
    "knockknock": "securityPrivacy",
    "ransomwhere": "securityPrivacy",
    "strongbox": "securityPrivacy",
    "macpass": "securityPrivacy",
    "authy": "securityPrivacy",
    "yubico-authenticator": "securityPrivacy",
    "duo-connect": "securityPrivacy",
    "private-internet-access": "securityPrivacy",
    "ivpn": "securityPrivacy",
    "clario": "securityPrivacy",
    "avast-security": "securityPrivacy",

    # Finance & Crypto
    "ledger-live": "financeCrypto",
    "exodus": "financeCrypto",
    "electrum": "financeCrypto",
    "trezor-suite": "financeCrypto",
    "wasabi-wallet": "financeCrypto",
    "sparrow": "financeCrypto",
    "portfolio-performance": "financeCrypto",
    "gnucash": "financeCrypto",
    "homebank": "financeCrypto",
    "moneymoney": "financeCrypto",
    "quicken": "financeCrypto",
    "copay": "financeCrypto",
    "bitcoin-core": "financeCrypto",
    "monero-gui": "financeCrypto",
    "tradingview": "financeCrypto",
    "blockstream-green": "financeCrypto",

    # Cloud & Storage
    "dropbox": "cloudStorage",
    "google-drive": "cloudStorage",
    "onedrive": "cloudStorage",
    "box-drive": "cloudStorage",
    "syncthing": "cloudStorage",
    "resilio-sync": "cloudStorage",
    "nextcloud": "cloudStorage",
    "owncloud": "cloudStorage",
    "mountain-duck": "cloudStorage",
    "expandrive": "cloudStorage",
    "arq": "cloudStorage",
    "backblaze": "cloudStorage",
    "carbon-copy-cloner": "cloudStorage",
    "superduper": "cloudStorage",
    "time-machine-editor": "cloudStorage",
    "chronosync": "cloudStorage",
    "goodsync": "cloudStorage",
    "sync": "cloudStorage",
    "mega": "cloudStorage",
    "tresorit": "cloudStorage",
    "insync": "cloudStorage",
    "maestral": "cloudStorage",
    "ftp-disk": "cloudStorage",
    "transmit": "developerTools",

    # Science & Education
    "rstudio": "scienceEducation",
    "anaconda": "scienceEducation",
    "miniconda": "scienceEducation",
    "miniforge": "scienceEducation",
    "mambaforge": "scienceEducation",
    "matlab": "scienceEducation",
    "wolfram-mathematica": "scienceEducation",
    "geogebra": "scienceEducation",
    "stellarium": "scienceEducation",
    "celestia": "scienceEducation",
    "scilab": "scienceEducation",
    "octave": "scienceEducation",
    "paraview": "scienceEducation",
    "fiji": "scienceEducation",
    "zotero": "scienceEducation",
    "mendeley-reference-manager": "scienceEducation",
    "jabref": "scienceEducation",
    "qgis": "scienceEducation",
    "anki": "scienceEducation",
    "spss": "scienceEducation",
    "stata": "scienceEducation",
    "texshop": "scienceEducation",
    "mactex": "scienceEducation",
    "lyx": "scienceEducation",
    "skim": "scienceEducation",
    "bibdesk": "scienceEducation",
    "jupyter-notebook-viewer": "scienceEducation",

    # Menu Bar
    "stats": "menuBar",
    "istat-menus": "menuBar",
    "bartender": "menuBar",
    "hiddenbar": "menuBar",
    "jordanbaird-ice": "menuBar",
    "dozer": "menuBar",
    "vanilla": "menuBar",
    "itsycal": "menuBar",
    "menumeters": "menuBar",
    "bitbar": "menuBar",
    "swiftbar": "menuBar",
    "xbar": "menuBar",
    "one-switch": "menuBar",
    "lungo": "menuBar",
    "hand-mirror": "menuBar",
    "pock": "menuBar",
    "clocker": "menuBar",
    "meetingbar": "menuBar",
    "timemachinestatus": "menuBar",
    "eul": "menuBar",
    "runcat": "menuBar",
    "aldente": "menuBar",
    "battery-buddy": "menuBar",
    "hot": "menuBar",
    "topnotch": "menuBar",
    "notchmeister": "menuBar",
    "airbuddy": "menuBar",
    "toothfairy": "menuBar",
    "bluetooth-screen-lock": "menuBar",
    "weather-bar-app": "menuBar",
    "swim": "menuBar",

    # Additional overrides for popular apps in "Other"
    "anydesk": "cloudStorage",
    "teamviewer": "cloudStorage",
    "parsec": "games",
    "appflowy": "productivity",
    "adguard": "securityPrivacy",
    "aerial": "videoMedia",
    "balsamiq-wireframes": "designGraphics",
    "handbrake": "videoMedia",
    "localsend": "cloudStorage",
    "utm": "developerTools",
    "parallels": "developerTools",
    "vmware-fusion": "developerTools",
    "virtualbox": "developerTools",
    "copilot-for-xcode": "developerTools",
    "chatgpt": "productivity",
    "claude": "productivity",
    "ollamac": "developerTools",
    "ollama": "developerTools",
    "lm-studio": "developerTools",
    "jan": "developerTools",
    "msty": "developerTools",
    "diffusionbee": "designGraphics",
    "draw-things": "designGraphics",
    "comfyui": "designGraphics",
    "stable-diffusion-webui": "designGraphics",
    "calibre": "productivity",
    "netnewswire": "communication",
    "reeder": "communication",
    "transmission": "cloudStorage",
    "qbittorrent": "cloudStorage",
    "deluge": "cloudStorage",
    "free-download-manager": "cloudStorage",
    "jdownloader": "cloudStorage",
    "motrix": "cloudStorage",
    "applite": "utilities",
    "cakebrew": "utilities",
    "batteries": "menuBar",
    "batfi": "menuBar",
    "coconutbattery": "menuBar",

    # Remaining popular apps that fall to Other
    "accord": "communication",
    "amazon-chime": "communication",
    "aliwangwang": "communication",
    "automattic-texts": "communication",
    "bria": "communication",
    "atext": "productivity",
    "bike": "productivity",
    "boss": "productivity",
    "bitrix24": "productivity",
    "bookmacster": "productivity",
    "breaktimer": "productivity",
    "ableset": "audioMusic",
    "abyssoft-teleport": "utilities",
    "airdash": "cloudStorage",
    "airdroid": "utilities",
    "airparrot": "videoMedia",
    "airserver": "videoMedia",
    "advancedrestclient": "developerTools",
    "appbox": "developerTools",
    "altserver": "developerTools",
    "approf": "developerTools",
    "cinder": "developerTools",
    "backyard-ai": "developerTools",
    "blitz-gg": "games",
    "bettershot": "utilities",
    "bezel": "developerTools",
    "blurscreen": "utilities",
    "burn": "utilities",
    "calhash": "utilities",
    "alifix": "utilities",
    "app-tamer": "utilities",
    "aladin": "scienceEducation",
    "beast2": "scienceEducation",
    "cellprofiler": "scienceEducation",
    "camerabag-photo": "designGraphics",
    "beersmith": "productivity",
    "brewy": "utilities",
}

# ─────────────────────────────────────────────────
# Token Prefix Rules
# ─────────────────────────────────────────────────

TOKEN_PREFIX_RULES = {
    "jetbrains-": "developerTools",
    "eclipse-": "developerTools",
    "android-": "developerTools",
    "dotnet-": "developerTools",
    "oracle-": "developerTools",
    "adobe-": "designGraphics",
    "affinity-": "designGraphics",
    "topaz-": "designGraphics",
    "ableton-": "audioMusic",
    "fabfilter-": "audioMusic",
    "izotope-": "audioMusic",
    "native-instruments-": "audioMusic",
    "navicat-": "developerTools",
    "dcp-": "videoMedia",
    "elgato-": "videoMedia",
    "synology-": "cloudStorage",
    "4k-": "videoMedia",
}

# ─────────────────────────────────────────────────
# Homepage Domain Rules
# ─────────────────────────────────────────────────

HOMEPAGE_DOMAIN_RULES = {
    "jetbrains.com": "developerTools",
    "rogueamoeba.com": "audioMusic",
    "fabfilter.com": "audioMusic",
    "objective-see.org": "securityPrivacy",
    "objective-see.com": "securityPrivacy",
}

# ─────────────────────────────────────────────────
# Keyword Rules (ordered by priority — first match wins)
# Each rule: (category, keywords_in_desc, keywords_in_name, negative_keywords)
# ─────────────────────────────────────────────────

KEYWORD_RULES = [
    # Browsers (very specific, check first)
    ("browsers", [
        "web browser", "browser",
    ], ["browser"], ["file browser", "database browser", "object browser", "s3 browser",
                     "code browser", "ftp browser", "s3 browser", "api browser"]),

    # Games
    ("games", [
        "game", "gaming", "emulator", "retro gaming", "game engine",
        "game launcher", "game manager", "rom ", "chess",
        "puzzle", "board game", "card game", "arcade",
        "rpg", "strategy game", "sandbox game",
        "minecraft", "game controller", "joystick",
        "crossword",
    ], ["game", "emulator", "chess"], ["gamification"]),

    # Security & Privacy
    ("securityPrivacy", [
        "password manager", "password vault", "vpn ", "virtual private network",
        "encrypt", "firewall", "antivirus", "anti-virus", "malware",
        "security", "2fa", "authenticator", "two-factor",
        "password", "keychain", "ad block", "ad-block", "adblocker",
        "content blocker", "network filter", "proxy-based ad",
        "gatekeeper", "quarantine", "self-sign",
        "spyware", "privacy", "secure access",
        "digital signature", "signature editor",
        "credential", "secrets manage",
    ], ["vpn", "security", "password", "encrypt", "adguard", "adblock",
        "privacy"], []),

    # Finance & Crypto
    ("financeCrypto", [
        "crypto", "bitcoin", "ethereum", "blockchain", "wallet",
        "finance", "accounting", "invoice", "tax", "budget",
        "trading", "stock", "portfolio", "banking", "ledger",
        "bookkeeping", "cryptocurrency", "defi ",
        "bank account", "expense", "receipt",
        "payment", "billing", "money",
    ], ["crypto", "wallet", "finance", "trading", "bitcoin",
        "money", "billing"], []),

    # Audio & Music
    ("audioMusic", [
        "audio", "music", "sound", " daw", "podcast",
        "synthesizer", " dj ", "instrument", " mix",
        "equalizer", "midi", "sampler", "metronome",
        "audio editor", "music player", "music stream",
        "audio record", "beat", " song", "singing",
        "guitar", "piano", "drum", "synth",
        "tuner", "pitch", "tone", "lossless",
        "spotify", "tidal", "deezer",
        "audio interface", "modular synth",
    ], ["audio", "music", "sound", "podcast", "radio", "synth"], []),

    # Video & Media
    ("videoMedia", [
        "video", "media player", "streaming", "screen record",
        "movie", "subtitle", "encoder", "transcoder",
        "video edit", "video player", "video download",
        "live stream", "multimedia", "iptv",
        "screensaver", "screen saver", "wallpaper",
        "live wallpaper", "airplay", "chromecast",
        "tv ", "apple tv", "gif ", "webcam",
        "screen mirror", "capture card",
    ], ["video", "media", "player", "stream", "screensaver", "wallpaper",
        "webcam", "iptv"], []),

    # Communication
    ("communication", [
        "chat", "message", "messenger", "email", "mail client",
        "video call", "conferencing", "voip", "team communication",
        "collaboration platform", "instant messaging",
        "voice chat", "text chat", "social network",
        "microblog", "rss reader", "feed reader",
        "discussion", "forum",
    ], ["chat", "mail", "messenger", "email", "discord"], []),

    # Design & Graphics
    ("designGraphics", [
        "design", "graphic", "image editor", "photo edit",
        "3d ", "vector", "animation", "drawing", "illustration",
        "cad", "ui design", "ux design", "prototyp",
        "color picker", "icon", "sketch", "wireframe",
        "image process", "image view", "image optim",
        "photo manage", "raw process", "font editor",
        "typography", "font manage", "pixel art",
        "mockup", "diagramm", "diagram tool",
        "render", "modeling", "modelling",
        "paint", "collage", "panorama",
        "logo ", "whiteboard", "visual ",
    ], ["design", "graphic", "photo", "draw", "paint", "sketch", "3d",
        "font editor", "diagram", "render"], []),

    # Science & Education
    ("scienceEducation", [
        "science", "math", "research", "statistics",
        "education", "learning", "academic", "laboratory",
        "simulation", "astronomy", "chemistry", "physics",
        "biology", "scientific", "reference manager",
        "citation", "latex", "tex ", "bibliography",
        "flashcard", "study", "molecule", "genome",
        "dna ", "sequence analysis", "bioinformat",
        "geographic", "gis ", "mapping",
        "corpus", "concordanc", "linguistic",
        "econometric", "data science",
    ], ["science", "math", "research", "education", "learn",
        "molecule", "astronomy", "gis"], []),

    # Cloud & Storage
    ("cloudStorage", [
        "cloud storage", "file sync", "backup", "file sharing",
        "cloud drive", "file transfer", "ftp client",
        "download manager", "torrent", "bittorrent",
        "cloud sync", "remote storage",
        "send file", "share file", "transfer file",
        "airdrop", "data transfer", "s3 ",
        "remote desktop", "remote access", "remotely",
        "remote control", "screen sharing", "vnc",
        "rdp", "ssh client",
    ], ["cloud", "sync", "backup", "drive", "torrent",
        "transfer", "remote"], []),

    # Menu Bar (check before utilities to catch menu bar apps)
    ("menuBar", [
        "menu bar", "menubar", "status bar", "system tray",
        "lives in your menu", "menu-bar", "notification area",
        "sits in menu bar", "sits in the menu bar",
        "resides in menu bar", "battery indicator",
        "battery management", "battery health",
    ], ["menubar", "menu-bar"], []),

    # Developer Tools
    ("developerTools", [
        "developer", "development tool", " ide ", "code editor",
        "programming", "compiler", "debugger", "terminal",
        "command-line", "command line", " cli ", "devops",
        "container", "kubernetes", " api ", "sdk",
        "package manager", "version control",
        "database", " sql", "nosql", "mongodb",
        "git client", "git gui", "diff tool",
        "text editor", "source code",
        "regex", "hex editor", "disassembl",
        "reverse engineering", "binary", "decompil",
        "software model", "uml", "graphql",
        "rest client", "http client",
        "server manage", "web server",
        "software stack", "local server",
        "virtual machine", "virtualiz",
        "hypervisor", "emulation platform",
        "docker", "ci/cd", "deploy",
        "log viewer", "log analysis",
        "profil", "benchmark",
        "ai coding", "ai agent", "copilot",
        "code assist", "llm ", "ai assist",
    ], ["developer", "code", "terminal", "git", "ide", "sql", "api",
        "graphql", "devops", "vm ", "virtual machine"], ["video codec"]),

    # Productivity (broad, check later)
    ("productivity", [
        "note", "todo", "task", "calendar",
        "office", "pdf", "productivity", "writing",
        "markdown", "word process", "spreadsheet",
        "presentation", "project management",
        "mind map", "outline", "planner",
        "clipboard", "snippet", "launcher",
        "automation", "workflow", "time track",
        "pomodoro", "focus", "distraction",
        "text expan", "keyboard shortcut",
        "organiz", "organis", "knowledge",
        "wiki", "document", "crm",
        "recipe", "cookbook", "shopping list",
        "read later", "reader",
        "dictation", "transcri", "translat",
        "ocr", "text recogni",
        "kanban", "scrum", "agile",
        "habit", "journal", "diary",
    ], ["note", "todo", "task", "calendar", "office", "pdf",
        "wiki", "reader", "translator"], []),

    # Utilities (catch-all for system tools)
    ("utilities", [
        "utility", "system", "monitor", "cleanup",
        "disk", "file manage", "archive", "converter",
        "window manage", "screenshot", "screen capture",
        "uninstall", "maintenance", "compress",
        "rename", "batch", "preview",
        "calculator", "clock", "timer",
        "display", "brightness", "volume",
        "fan control", "temperature",
        "network tool", "network util",
        "system info", "system prefer",
        "finder", "dock", "desktop",
        "input method", "keyboard layout",
        "driver", "firmware",
        "configurator", "configuration tool",
        "tweak", "customiz", "customis",
        "cleaner", "optimizer", "optimiser",
        "unarchiv", "zip", "extract",
        "mount", "dmg", "iso",
        "usb ", "flash drive",
        "clipboard manage", "quick look",
        "spotlight", "search tool",
        "gesture", "trackpad", "touchpad",
        "mouse", "keyboard", "remap",
        "notification", "alert",
        "app manage", "install",
        "helper", "companion app",
        "format", "erase", "partition",
        "log ", "console",
        "inspect", "analyz", "analyse",
    ], ["util", "tool", "manager", "monitor", "clean",
        "helper", "inspector", "viewer", "converter"], []),
]


def classify_cask(cask):
    """Classify a single cask into a category."""
    token = cask.get("token", "")
    name = (cask.get("name", [None])[0] or token).lower()
    desc = (cask.get("desc") or "").lower()
    homepage = (cask.get("homepage") or "").lower()
    text = f"{name} {desc}"

    # Priority 1: Manual overrides
    if token in MANUAL_OVERRIDES:
        return MANUAL_OVERRIDES[token]

    # Priority 2: Token prefix rules
    for prefix, category in TOKEN_PREFIX_RULES.items():
        if token.startswith(prefix):
            return category

    # Priority 3: Homepage domain rules
    for domain, category in HOMEPAGE_DOMAIN_RULES.items():
        if domain in homepage:
            return category

    # Priority 4: Keyword matching
    for category, desc_keywords, name_keywords, negative_keywords in KEYWORD_RULES:
        # Check negative keywords first
        if any(neg in text for neg in negative_keywords):
            continue

        # Check description keywords
        if any(kw in desc for kw in desc_keywords):
            return category

        # Check name keywords
        if any(kw in name for kw in name_keywords):
            return category

    # Default
    return "other"


def main():
    print("Fetching casks from Homebrew API...")
    url = "https://formulae.brew.sh/api/cask.json"
    with urllib.request.urlopen(url) as response:
        casks = json.loads(response.read().decode())

    print(f"Total casks: {len(casks)}")

    # Filter like the app does
    active = [
        c for c in casks
        if not c.get("deprecated")
        and not c.get("disabled")
        and "@" not in c["token"]
        and not c["token"].startswith("font-")
    ]

    print(f"Active (non-font, non-deprecated): {len(active)}")

    # Classify
    token_to_category = {}
    category_counts = {cat: 0 for cat in CATEGORIES}

    for cask in active:
        category = classify_cask(cask)
        token_to_category[cask["token"]] = category
        category_counts[category] += 1

    # Print stats
    print("\n── Classification Results ──")
    for cat in CATEGORIES:
        count = category_counts[cat]
        pct = (count / len(active)) * 100
        bar = "█" * int(pct / 2)
        print(f"  {cat:20s}  {count:5d}  ({pct:5.1f}%)  {bar}")

    print(f"\n  Total classified: {len(token_to_category)}")

    # Build output
    output = {
        "version": 1,
        "generatedDate": str(date.today()),
        "totalCasks": len(token_to_category),
        "categories": {cat: {"displayName": display_name(cat), "icon": icon_for(cat)}
                       for cat in CATEGORIES},
        "tokenToCategory": token_to_category,
    }

    # Write JSON
    output_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                              "CaskHub", "Resources")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "categories.json")

    with open(output_path, "w") as f:
        json.dump(output, f, indent=2, sort_keys=False)

    print(f"\nWritten to: {output_path}")

    # Print some samples from each category
    print("\n── Samples per Category ──")
    for cat in CATEGORIES:
        samples = [t for t, c in token_to_category.items() if c == cat][:5]
        print(f"  {cat}: {', '.join(samples)}")


def display_name(category_id):
    """Convert camelCase ID to display name."""
    names = {
        "developerTools": "Developer Tools",
        "browsers": "Browsers",
        "communication": "Communication",
        "productivity": "Productivity",
        "utilities": "Utilities",
        "designGraphics": "Design & Graphics",
        "audioMusic": "Audio & Music",
        "videoMedia": "Video & Media",
        "games": "Games",
        "securityPrivacy": "Security & Privacy",
        "financeCrypto": "Finance & Crypto",
        "cloudStorage": "Cloud & Storage",
        "scienceEducation": "Science & Education",
        "menuBar": "Menu Bar",
        "other": "Other",
    }
    return names.get(category_id, category_id)


def icon_for(category_id):
    """SF Symbol icon for each category."""
    icons = {
        "developerTools": "chevron.left.forwardslash.chevron.right",
        "browsers": "globe",
        "communication": "bubble.left.and.bubble.right",
        "productivity": "checkmark.circle",
        "utilities": "wrench.and.screwdriver",
        "designGraphics": "paintbrush",
        "audioMusic": "music.note",
        "videoMedia": "play.rectangle",
        "games": "gamecontroller",
        "securityPrivacy": "lock.shield",
        "financeCrypto": "dollarsign.circle",
        "cloudStorage": "cloud",
        "scienceEducation": "graduationcap",
        "menuBar": "menubar.rectangle",
        "other": "square.grid.2x2",
    }
    return icons.get(category_id, "questionmark")


if __name__ == "__main__":
    main()
