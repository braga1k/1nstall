# Mac catalog — 0.5.0 beta 1

112 Mac entries, 25 categories, 20 profiles. 33 entries support reviewed Homebrew installation; 79 open the Mac App Store or the official publisher. A source page opening is never reported as a successful installation.

This is a Mac-specific catalog. Windows 3.5 contains 325 entries: the beta does not claim equal coverage. Cross-platform tools sit alongside Mac alternatives, with photography, documents, cloud storage, gaming, terminals, Git, databases, virtualisation and AI categories. Profiles select apps for review; they do not silently install software.

Metadata reviewed on 2026-10-04 against [Homebrew's API](https://formulae.brew.sh/docs/api/), official vendors and Apple's Mac software listings. Homebrew download events are not a measure of global usage. The list combines the initial 60-app research, Windows overlap and Mac-specific use cases; it is not a popularity ranking.

## What “reviewed” means

- The 33 automatic entries passed preflight on the validation Mac: matching version, SHA-256, a single expected app target and bounded installer/uninstaller artifacts. Unsupported scripts, PKG actions and changed metadata are refused. Homebrew must already be installed; 1nstall does not install it silently.
- Maccy 2.7.1 and Skim 1.7.17 passed new disposable install/verify/remove cycles in this beta. Rectangle and IINA passed equivalent earlier cycles. The other entries have metadata review, not end-to-end installation coverage.
- “Confirm at source” means the cask did not provide a useful minimum and a verified minimum remains outstanding. These entries use official guided installation. Architecture labels are based on vendor/store or Homebrew arm64 variants, not a binary audit of every application. “Mac App Store” delegates compatibility to the store.
- The current Final Cut Pro and Motion listings require macOS 26.6. They remain discoverable with a newer-macOS warning on the validation Mac running 26.5.2. Older versions and purchase eligibility are controlled by Apple.
- Firefox has language-specific artifacts; this beta opens its official download. Vivaldi had divergent versions in the per-cask API and locally resolved Homebrew metadata, so automatic installation is withheld. Disabled darktable/digiKam casks and the deprecated separate Codex cask were excluded. The current ChatGPT desktop product is included.
- Apple search can return iOS results even for a Mac query. Only entries explicitly returned as `mac-software` supplied the new Mac Store records. Other search responses are research evidence, not proof of Mac support.

[Review evidence](research/beta/catalog-review.json) · [Vendor checks](research/beta/official-sources.json) · [Removal coverage](REMOVAL.md)

## Entries

| App | Category | Install method | Reviewed version | Minimum macOS | Architecture basis | Official source |
| --- | --- | --- | --- | --- | --- | --- |
| 1Password | security | Publisher | 8.12.38 | 12 | Apple Silicon | [Open](https://1password.com/) |
| Ableton Live Lite | audio | Homebrew (reviewed) | 12.4.6 | 11 | Universal | [Open](https://www.ableton.com/en/products/live-lite/) |
| Affinity | design | Publisher | 3.3.0,4850 | Confirm at source | Apple Silicon | [Open](https://www.affinity.studio/) |
| Alfred | productivity | Publisher | 5.8.1,2349 | 10.14 | Apple Silicon | [Open](https://www.alfredapp.com/) |
| Android Studio | development | Publisher | 2026.2.1.8,rabbit1 | Confirm at source | Apple Silicon | [Open](https://developer.android.com/studio/) |
| Atlassian SourceTree | git | Publisher | 4.2.19,317 | Confirm at source | Apple Silicon | [Open](https://www.sourcetreeapp.com/) |
| Audacity | audio | Publisher | 4.0.1 | Confirm at source | Apple Silicon | [Open](https://www.audacityteam.org/) |
| BBEdit | development | Publisher | 16.0.3 | 14 | Apple Silicon | [Open](https://www.barebones.com/products/bbedit/) |
| Bear | notes | Mac App Store | 3.0.1 | 12.4 | Mac App Store | [Open](https://apps.apple.com/pt/app/bear-anota%C3%A7%C3%B5es-particulares/id1091189122?mt=12&uo=4) |
| BetterDisplay | productivity | Publisher | 5.0.6 | Confirm at source | Apple Silicon | [Open](https://betterdisplay.pro/) |
| Bitwarden | security | Homebrew (reviewed) | 2026.9.1 | 12 | Universal | [Open](https://bitwarden.com/) |
| Blender | design | Publisher | 5.2.2 | Confirm at source | Apple Silicon | [Open](https://www.blender.org/) |
| Brave | browsers | Homebrew (reviewed) | 1.96.61.0 | 13 | Apple Silicon | [Open](https://brave.com/) |
| calibre | documents | Publisher | 9.15.0 | Confirm at source | Apple Silicon | [Open](https://calibre-ebook.com/) |
| Canva | design | Homebrew (reviewed) | 1.126.0 | 12 | Universal | [Open](https://www.canva.com/download/) |
| CapCut | video | Publisher | 9.5.0.4590 | Confirm at source | Apple Silicon | [Open](https://www.capcut.com/) |
| ChatGPT | ai | Homebrew (reviewed) | 26.930.41038 | 14 | Apple Silicon | [Open](https://chatgpt.com/download/) |
| Claude | ai | Homebrew (reviewed) | 2.19675.0,5706e5524dba58b23e105c31c358df8ab0a95852 | 13 | Universal | [Open](https://claude.com/download) |
| Cryptomator | security | Publisher | 1.19.3 | Confirm at source | Apple Silicon | [Open](https://cryptomator.org/) |
| Cursor | development | Homebrew (reviewed) | 3.23.12,2d29876d567da1607532b23bbf2cd5ddbca496fe | 12 | Apple Silicon | [Open](https://www.cursor.com/) |
| Cyberduck | transfer | Publisher | 9.5.4,45528 | Confirm at source | Apple Silicon | [Open](https://cyberduck.io/) |
| DaVinci Resolve | video | Mac App Store | 21.1 | 15.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/davinci-resolve/id571213070?mt=12&uo=4) |
| DBeaver Community Edition | databases | Publisher | 26.2.1 | Confirm at source | Apple Silicon | [Open](https://dbeaver.io/) |
| Discord | communication | Publisher | 0.0.414 | 12 | Apple Silicon | [Open](https://discord.com/) |
| Docker Desktop | virtualization | Publisher | 4.93.0,240920 | 14 | Apple Silicon | [Open](https://www.docker.com/products/docker-desktop) |
| Dropbox | cloud | Publisher | 272.4.3798 | Confirm at source | Apple Silicon | [Open](https://www.dropbox.com/) |
| Epic Games Launcher | gaming | Publisher | 20.3.3 | 13 | Apple Silicon | [Open](https://www.epicgames.com/) |
| Etcher | system | Publisher | 2.1.7 | Confirm at source | Apple Silicon | [Open](https://balena.io/etcher) |
| Figma | design | Publisher | 126.9.11 | Confirm at source | Apple Silicon | [Open](https://www.figma.com/) |
| Final Cut Pro | video | Mac App Store | 12.4 | 26.6 | See App Store | [Open](https://apps.apple.com/pt/app/final-cut-pro/id424389933?mt=12&uo=4) |
| Firefox | browsers | Publisher | 157.0 | 10.15 | Apple Silicon | [Open](https://www.mozilla.org/firefox/) |
| Fork | git | Publisher | 2.70.2 | Confirm at source | Apple Silicon | [Open](https://fork.dev/) |
| AppCleaner | system | Publisher | 3.7 | 15 | Apple Silicon | [Open](https://freemacsoft.net/appcleaner/) |
| GarageBand | audio | Mac App Store | 10.4.14 | 15.6 | Mac App Store | [Open](https://apps.apple.com/pt/app/garageband/id682658836?mt=12&uo=4) |
| Ghostty | terminals | Publisher | 1.3.1 | 13 | Apple Silicon | [Open](https://ghostty.org/) |
| GIMP | photos | Publisher | 3.2.6 | Confirm at source | Apple Silicon | [Open](https://www.gimp.org/) |
| GitHub Desktop | git | Homebrew (reviewed) | 3.6.6-8b85519e | 12 | Apple Silicon | [Open](https://desktop.github.com/) |
| Google Chrome | browsers | Publisher | 154.0.8037.98 | 13 | Universal | [Open](https://www.google.com/chrome/) |
| Google Drive | cloud | Publisher | 132.0.0 | 13 | Apple Silicon | [Open](https://www.google.com/drive/) |
| HandBrake | video | Homebrew (reviewed) | 1.11.2 | 10.13 | Apple Silicon | [Open](https://handbrake.fr/) |
| Heroic Games Launcher | gaming | Publisher | 2.22.3 | 12 | Apple Silicon | [Open](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/) |
| Ice | productivity | Homebrew (reviewed) | 0.11.12 | 14 | Apple Silicon | [Open](https://icemenubar.app/) |
| IINA | players | Homebrew (reviewed) | 1.5.0 | 12 | Apple Silicon | [Open](https://iina.io/) |
| Inkscape | design | Publisher | 1.4.4 | Confirm at source | Apple Silicon | [Open](https://inkscape.org/) |
| Insomnia | development | Homebrew (reviewed) | 13.3.0 | 12 | Apple Silicon | [Open](https://insomnia.rest/) |
| iTerm2 | terminals | Homebrew (reviewed) | 3.7.3 | 13 | Apple Silicon | [Open](https://iterm2.com/) |
| Karabiner Elements | system | Publisher | 16.3.0 | Confirm at source | Apple Silicon | [Open](https://karabiner-elements.pqrs.org/) |
| KeePassXC | security | Publisher | 2.7.12 | 12 | Apple Silicon | [Open](https://keepassxc.org/) |
| Keka | archives | Homebrew (reviewed) | 1.6.8 | 10.10 | Apple Silicon | [Open](https://www.keka.io/) |
| Krita | design | Publisher | 5.3.4 | Confirm at source | Apple Silicon | [Open](https://krita.org/) |
| LibreOffice | office | Homebrew (reviewed) | 26.8.0 | 11 | Apple Silicon | [Open](https://www.libreoffice.org/) |
| LinearMouse | productivity | Publisher | 0.12.0 | Confirm at source | Apple Silicon | [Open](https://linearmouse.org/) |
| Little Snitch | network | Publisher | 6.5 | 14 | Apple Silicon | [Open](https://www.obdev.at/products/littlesnitch/index.html) |
| LM Studio | ai | Homebrew (reviewed) | 0.4.25,1 | 12 | Apple Silicon | [Open](https://lmstudio.ai/) |
| LocalSend | transfer | Homebrew (reviewed) | 1.18.2 | 11 | Apple Silicon | [Open](https://localsend.org/) |
| Logic Pro | audio | Mac App Store | 12.4 | 15.4 | See App Store | [Open](https://apps.apple.com/pt/app/logic-pro/id634148309?mt=12&uo=4) |
| LosslessCut | video | Publisher | 3.69.0 | 12 | Apple Silicon | [Open](https://github.com/mifi/lossless-cut) |
| Maccy | productivity | Homebrew (reviewed) | 2.7.1 | 14 | Apple Silicon | [Open](https://maccy.app/) |
| Magnet | productivity | Mac App Store | 3.0.7 | 13.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/magnet/id441258766?mt=12&uo=4) |
| Microsoft Edge | browsers | Publisher | 154.0.4258.53,559421d7-1ab9-4b4d-bbe2-6578175c72ec | 13 | Apple Silicon | [Open](https://www.microsoft.com/en-us/edge?form=) |
| Microsoft Excel | office | Mac App Store | 16.113.3 | 14.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/microsoft-excel/id462058435?mt=12&uo=4) |
| Microsoft OneNote | notes | Mac App Store | 16.113.3 | 14.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/microsoft-onenote/id784801555?mt=12&uo=4) |
| Microsoft Outlook | mail | Mac App Store | 16.113.3 | 14.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/microsoft-outlook/id985367838?mt=12&uo=4) |
| Microsoft PowerPoint | office | Mac App Store | 16.113.3 | 14.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/microsoft-powerpoint/id462062816?mt=12&uo=4) |
| Microsoft Word | office | Mac App Store | 16.113.3 | 14.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/microsoft-word/id462054704?mt=12&uo=4) |
| Motion | video | Mac App Store | 6.4 | 26.6 | See App Store | [Open](https://apps.apple.com/pt/app/motion/id434290957?mt=12&uo=4) |
| Mozilla Thunderbird | mail | Publisher | 157.0.1 | Confirm at source | Apple Silicon | [Open](https://www.thunderbird.net/en-US/) |
| Notion | notes | Homebrew (reviewed) | 7.36.1 | 12 | Apple Silicon | [Open](https://www.notion.com/) |
| OBS Studio | video | Publisher | 32.2.2 | 13 | Apple Silicon | [Open](https://obsproject.com/) |
| Obsidian | notes | Homebrew (reviewed) | 1.13.7 | 12 | Apple Silicon | [Open](https://obsidian.md/) |
| Ollama | ai | Publisher | 0.35.1 | 14 | Apple Silicon | [Open](https://ollama.com/) |
| OneDrive | cloud | Publisher | 26.153.0809.0004 | 14 | Universal | [Open](https://www.microsoft.com/en-us/microsoft-365/onedrive/online-cloud-storage) |
| ONLYOFFICE | office | Publisher | 9.4.0 | Confirm at source | Apple Silicon | [Open](https://www.onlyoffice.com/) |
| OnyX | system | Publisher | 5.0.5 | Confirm at source | Apple Silicon | [Open](https://www.titanium-software.fr/en/onyx.html) |
| Opera | browsers | Homebrew (reviewed) | 136.0.6008.80 | 13 | Apple Silicon | [Open](https://www.opera.com/) |
| OrbStack | virtualization | Publisher | 2.2.3,20963 | 14 | Apple Silicon | [Open](https://orbstack.dev/) |
| PDF Expert | documents | Homebrew (reviewed) | 3.13.4,1177 | 12 | Apple Silicon | [Open](https://pdfexpert.com/) |
| Pearcleaner | system | Publisher | 5.4.3 | 13 | Apple Silicon | [Open](https://itsalin.com/appInfo/?id=pearcleaner) |
| Pixelmator Pro | photos | Mac App Store | 3.8 | 12.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/pixelmator-pro/id1289583905?mt=12&uo=4) |
| Postman | development | Publisher | 12.30.6 | Confirm at source | Apple Silicon | [Open](https://www.postman.com/) |
| Proton Mail | mail | Publisher | 1.15.1 | 12 | Apple Silicon | [Open](https://proton.me/mail) |
| ProtonVPN | network | Publisher | 6.5.1 | 14 | Apple Silicon | [Open](https://protonvpn.com/) |
| RawTherapee | photos | Publisher | 5.13 | 26 | Universal | [Open](https://rawtherapee.com/) |
| Raycast | productivity | Homebrew (reviewed) | 2.6.2.0 | 26 | Apple Silicon | [Open](https://www.raycast.com/new) |
| REAPER | audio | Publisher | 7.81 | Confirm at source | Universal | [Open](https://www.reaper.fm/) |
| Rectangle | productivity | Homebrew (reviewed) | 2.0.2 | 14 | Apple Silicon | [Open](https://rectangleapp.com/) |
| Shotcut | video | Homebrew (reviewed) | 26.9.28,26.9.27 | 12 | Apple Silicon | [Open](https://www.shotcut.org/) |
| Shutter Encoder | video | Publisher | 20.4 | Confirm at source | Apple Silicon | [Open](https://www.shutterencoder.com/) |
| Signal | communication | Homebrew (reviewed) | 8.29.0 | 13 | Apple Silicon | [Open](https://signal.org/) |
| Skim | documents | Homebrew (reviewed) | 1.7.17 | 10.13 | Apple Silicon | [Open](https://skim-app.sourceforge.io/) |
| Slack | communication | Homebrew (reviewed) | 4.52.171 | 13 | Apple Silicon | [Open](https://slack.com/) |
| Spotify | players | Publisher | 1.3.3.264 | 13 | Apple Silicon | [Open](https://www.spotify.com/) |
| Steam | gaming | Publisher | 6.0 | Confirm at source | Intel · Rosetta 2 | [Open](https://store.steampowered.com/about/) |
| Sublime Text | development | Publisher | 4215 | Confirm at source | Apple Silicon | [Open](https://www.sublimetext.com/) |
| Syncthing | cloud | Homebrew (reviewed) | 2.1.5-1 | 12 | Apple Silicon | [Open](https://syncthing.net/) |
| TablePlus | databases | Publisher | 26.10.22,802 | Confirm at source | Apple Silicon | [Open](https://tableplus.com/) |
| Tailscale | network | Mac App Store | 1.102.4 | 12.4 | Mac App Store | [Open](https://apps.apple.com/pt/app/tailscale/id1475387142?mt=12&uo=4) |
| Telegram for macOS | communication | Homebrew (reviewed) | 12.10,282985 | 10.13 | Apple Silicon | [Open](https://macos.telegram.org/) |
| The Unarchiver | archives | Mac App Store | 4.3.9 | 10.13 | Mac App Store | [Open](https://apps.apple.com/pt/app/the-unarchiver/id425424353?mt=12&uo=4) |
| Things 3 | productivity | Mac App Store | 3.24.1 | 13.3 | Mac App Store | [Open](https://apps.apple.com/pt/app/things-3/id904280696?mt=12&uo=4) |
| Todoist | productivity | Mac App Store | 9.30.0 | 12.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/todoist-to-do-list-calend%C3%A1rio/id585829637?mt=12&uo=4) |
| Transmission | transfer | Publisher | 4.1.3 | Confirm at source | Apple Silicon | [Open](https://transmissionbt.com/) |
| UTM | virtualization | Homebrew (reviewed) | 4.7.5 | 11.3 | Apple Silicon | [Open](https://mac.getutm.app/) |
| VeraCrypt | security | Publisher | 1.26.29 | Confirm at source | Apple Silicon | [Open](https://veracrypt.io/) |
| Visual Studio Code | development | Publisher | 1.140.0 | Confirm at source | Apple Silicon | [Open](https://code.visualstudio.com/) |
| Vivaldi | browsers | Publisher | 8.2.4133.83 | 13 | Universal | [Open](https://vivaldi.com/) |
| VLC | players | Homebrew (reviewed) | 3.0.24 | 10.7 | Apple Silicon | [Open](https://www.videolan.org/vlc/) |
| WhatsApp | communication | Homebrew (reviewed) | 26.39.21 | 12 | Apple Silicon | [Open](https://www.whatsapp.com/) |
| WireGuard | network | Mac App Store | 1.0.16 | 12.0 | Mac App Store | [Open](https://apps.apple.com/pt/app/wireguard/id1451685025?mt=12&uo=4) |
| Zed | development | Publisher | 1.22.0 | Confirm at source | Apple Silicon | [Open](https://zed.dev/) |
| Zen Browser | browsers | Publisher | 1.23b | Confirm at source | Universal | [Open](https://zen-browser.app/) |
| Zoom | communication | Publisher | 7.2.2.88465 | Confirm at source | Apple Silicon | [Open](https://www.zoom.us/) |
