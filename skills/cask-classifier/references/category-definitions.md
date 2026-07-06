# CaskHub Category Definitions

Complete definitions for all 18 categories with inclusion criteria, exclusion criteria, and boundary examples.

## developerTools — Developer Tools

**Definition**: IDEs, code editors, version control, API clients, databases, SDKs, terminal emulators, debuggers, CI/CD tools, containers, build tools, package managers, cloud CLIs.

**Inclusion criteria**:
- The primary user is a software developer, DevOps engineer, or hardware engineer
- The app helps write, test, deploy, or manage code/infrastructure
- IDEs and code editors (VS Code, Xcode, IntelliJ)
- Git clients and version control (GitUp, PlasticSCM, Kactus)
- Database tools — SQL clients, editors, browsers (Base, SQuirreL SQL, Aqua Data Studio, SQLEditor)
- SSH/SFTP clients (Termius, Electerm, PortX)
- Terminal emulators (iTerm2, Wave, Contour, Archipelago, ZOC)
- Cloud CLI tools (gcloud-cli, aws-cli, ibm-cloud-cli)
- JDK/SDK distributions (Corretto, Temurin, GraalVM, Zulu, SapMachine)
- Game development tools (Unity Hub, Tiled, TexturePacker, GameMaker)
- Programming languages and runtimes (R, Node.js)
- API development platforms (Anypoint Studio, Postman)
- Visual development tools where the OUTPUT is code (FlutterFlow, Bootstrap Studio, Fuse Open)
- Developer utilities (DevToys, Sherlock iOS debugger, Rivet AI dev tool)
- Network simulators (GNS3)
- Docker/Kubernetes tools (Captain, Kubeterm)
- PCB/electronics design tools — EDA (KiCad, Arduino IDE) because the primary user is an engineer
- Server software (CrushFTP, Transfer, Trivial)
- Deployment tools (AutoDMG)

**Exclusion criteria**:
- NOT apps that happen to have a developer as a secondary user
- NOT games just because they use a game engine

**Tricky boundary cases**:
- **R** (r-app): "statistical computing and graphics" — the "graphics" means data plots/charts. Primary user is a data scientist writing R code → developerTools
- **KiCad**: "electronics design automation" — "design" here means PCB engineering, not graphic design → developerTools
- **Bootstrap Studio**: "design and prototype websites" — the output is HTML/CSS code → developerTools
- **PaintCode**: Turns vector drawings into Obj-C/Swift code — dual purpose → designGraphics (primary) + developerTools (secondary)

## browsers — Browsers

**Definition**: Web browsers ONLY — applications whose primary purpose is browsing the internet.

**Inclusion criteria**:
- General web browsers (Chrome, Firefox, Safari, Arc, Brave, Vivaldi)
- Privacy-focused browsers (Tor Browser, DuckDuckGo, Mullvad)
- Anti-detect browsers (GoLogin, Donut, Kameleo)
- Gaming browsers (Opera GX)
- Specialized browsers (Safe Exam Browser)

**Exclusion criteria**:
- NOT database/file/API browsers
- NOT web app wrappers whose purpose is app organization (Biscuit → productivity)
- NOT developer testing tools that look like browsers (Blisk, Polypane, Responsively → developerTools)
- NOT Electron wrapper apps

## communication — Communication

**Definition**: Apps for person-to-person communication: chat, email, video conferencing, VoIP, social media clients.

**Inclusion criteria**:
- Messaging apps (Telegram, Signal, Discord, Slack, WhatsApp)
- Email clients (Thunderbird, Spark, Mimestream)
- Video conferencing (Zoom, Teams, WebEx, Alfaview)
- VoIP/softphones (Bria, SIPgate)
- Social media clients (Mastodon, Bluesky)
- IRC clients (Textual, Halloy)
- Team collaboration platforms centered on chat (Jandi, Lark, Flock)

**Exclusion criteria**:
- NOT AI chatbots/LLM clients → productivity
- NOT RSS readers → productivity
- NOT news apps → productivity
- NOT developer tools that happen to be chat-like (WeChat DevTools → developerTools)
- NOT encryption tools (GPG Suite → securityPrivacy)

**Tricky boundary cases**:
- **Jandi**: Team collaboration tool with messaging — communication (primary) + productivity (secondary)
- **Miro**: Online whiteboard — collaboration/communication (primary) + productivity (secondary)
- **Proton Mail**: Encrypted email — communication (the encryption is a feature, not the purpose)

## officeTools — Office Tools

**Definition**: Office suites, document editors, spreadsheet applications, and their language packs/extensions. Apps whose primary purpose is creating/editing office documents (word processing, spreadsheets, presentations).

**Inclusion criteria**:
- Full office suites (LibreOffice, Microsoft Office, WPS Office, ONLYOFFICE, SoftMaker FreeOffice)
- Office suite variants and language packs (LibreOffice Still, LibreOffice Language Pack)
- Document safety/conversion tools specifically for office formats (Dangerzone)
- Office project management tools (Revolver Office)

**Exclusion criteria**:
- NOT "virtual office" remote work tools (Tandem, Roam → productivity) — these are workspace/collaboration tools, not document editors
- NOT standalone Markdown/text editors → productivity
- NOT standalone PDF editors → productivity
- NOT presentation-only tools (Deckset, iA Presenter → productivity)

**Boundary rule**: If an app's primary function is creating/editing office documents (word, spreadsheet, presentation) in a traditional office suite format, it belongs here. If it's a lightweight writing/note tool, it stays in productivity.

## productivity — Productivity

**Definition**: Note-taking, task management, calendars, writing tools, clipboard managers, text expanders, AI assistants/chatbots, RSS readers, PDF editors, project management, digital signatures, virtual office/remote work tools.

**Inclusion criteria**:
- Note-taking (Obsidian, Notion, Roam Research, Bear, Reflect)
- Task management (Todoist, Things, Sleek)
- AI chat clients / LLM interfaces (ChatGPT, Poe, BoltAI, Chatbox, AnythingLLM)
- RSS readers (NetNewsWire, FeedFlow)
- Mind mapping (MindManager, SimpleMind, TheBrain, Milanote)
- PDF reading/editing (Skim, PDF Pals)
- Digital signature / e-signing (AutoFirma, GoSign, Podpisuj)
- Markdown editors (MacDown)
- Presentation tools (Deckset, iA Presenter)
- Transcription tools (QuickWhisper, ExpressScribe)
- Web app organizers (Biscuit)
- WordPress blogging client (WordPress.com)
- Shopping/merchant tools (Taobao, AliWorkbench)
- News readers (QQNews)

**Exclusion criteria**:
- NOT actual messaging/email apps → communication
- NOT code editors → developerTools

## utilities — Utilities

**Definition**: System utilities, file managers, disk tools, backup, uninstallers, converters, system monitoring, drivers, input methods, remote desktop, download managers, torrent clients, file transfer tools, hardware companions.

**Inclusion criteria**:
- System monitoring (iStatistica, Activity Monitor replacements)
- File managers (ForkLift, Spacedrive)
- Remote desktop (TeamViewer, AnyDesk, RustDesk, NoMachine, Parsec, VNC)
- Download managers (JDownloader, Motrix, Free Download Manager)
- Torrent clients (Transmission, BiglyBT)
- File transfer (LocalSend, FlyingCarpet, Send Anywhere)
- Backup tools (Carbon Copy Cloner, SuperDuper, Vorta, Time Machine tools)
- Printer/USB/serial drivers (all hardware drivers)
- Keyboard configurators (Bazecor for Dygma keyboards)
- Input methods and keyboard layouts (Jyutping, Bepo, QWERTY-FR, WeType)
- Hardware companion software (Bose Updater, Jabra Direct, Creative, 8BitDo, SteelSeries GG)
- Window management (Swish, Rectangle)
- Screen sharing tools (AirTame, Bananas)
- App launchers (Overflow)
- System preferences tools (PrefsEditor)
- GPU monitoring (gfxCardStatus)
- VM runners (Vimy, Viables)
- Mac deployment (MDS)
- Wine wrappers (PlayOnMac, CrossOver)
- OCR tools (TextSniper, TextGrabber2)
- Noise cancellation utilities (Krisp, RNNoise, Utterly)
- Duplicate photo finders (PhotoSweeper-X)
- Menu bar weather (Meteorologist)

**Exclusion criteria**:
- NOT developer-oriented tools → developerTools
- NOT cloud storage services → cloudStorage

**The catch-all rule**: When genuinely uncertain between utilities and another category, utilities is the safe default for system/hardware tools.

## designGraphics — Design & Graphics

**Definition**: Apps whose output is VISUAL ASSETS — images, photos, illustrations, icons, 3D models, UI/UX mockups, digital art.

**Inclusion criteria**:
- Image/photo editors (Photoshop, GIMP, Pixelmator)
- Vector editors (Illustrator, Inkscape, Affinity Designer)
- 3D modeling (Blender, Cinema 4D)
- UI/UX design (Figma, Sketch)
- Icon editors, pixel art tools
- Color pickers
- Screenshot annotation tools
- CAD software
- AI image generation (Runway ML)
- Photo library management for photographers (Excire Foto)
- Astrophotography processing (StarNet++)
- Design collection tools (Scrapp)

**Exclusion criteria — THE CRITICAL LIST**:
- NOT "design" in PCB/electronics context (KiCad → developerTools)
- NOT "design" in SQL/database context (SQLEditor → developerTools)
- NOT "design" in web development context (Bootstrap Studio → developerTools)
- NOT "graphical" meaning "has a GUI" (SQuirrelSQL, Kubeterm → developerTools)
- NOT "graphics" meaning data visualization (R → developerTools)
- NOT "visual" meaning visual programming (FlutterFlow, Cables → developerTools)
- NOT visual whiteboards (Miro → communication, Milanote → productivity)
- NOT system monitoring with charts (iStatistica → utilities)
- NOT GPU monitors (gfxCardStatus → utilities)
- NOT VM tools (Vimy, Viables → utilities)

**Dual-purpose apps** (keep in designGraphics + add secondary):
- PaintCode: design → code (+ developerTools secondary)
- PixelSnap: screen measurement for design AND development (+ developerTools secondary)
- Google Web Designer: HTML5 design AND development (+ developerTools secondary)
- Kactus: Sketch design + Git version control (+ developerTools secondary)
- RapidWeaver: web design AND development (+ developerTools secondary)
- DJV: VFX image viewer AND video production (+ videoMedia secondary)

## audioMusic — Audio & Music

**Definition**: DAWs, music players, audio editors, synthesizers, DJ software, podcast tools, audio plugins (VST/AU), music streaming, music notation, MIDI tools.

**Inclusion criteria**: Apps for creating, editing, playing, or managing music and audio content.

**Exclusion criteria**:
- NOT video conferencing (Alfaview → communication)
- NOT hardware firmware updaters (Bose Updater → utilities)
- NOT keyboard input methods (Jyutping → utilities)
- NOT game trackers (HSTracker → games)
- NOT system monitoring (osquery → developerTools)
- NOT noise cancellation utilities (Krisp → utilities)
- NOT screen recorders (Screenflick → videoMedia)
- NOT hardware companion software that configures audio devices (Jabra Direct → utilities)
- NOT screensavers (Musaicfm → utilities)
- NOT Discord integrations (Music Presence → utilities)
- NOT games (Clone Hero → games)
- NOT electronic test equipment (Waveforms → scienceEducation)

## videoMedia — Video & Media

**Definition**: Video players, video editors, screen recorders, streaming software (OBS), video converters, media servers, webcam tools, subtitle editors.

**Inclusion criteria**:
- Video players (VLC, IINA, mpv)
- Video editors (DaVinci Resolve, Final Cut Pro, Shotcut)
- Screen recorders (OBS, Screenflick, ScreenFlow)
- Streaming software (OBS, Streamlabs)
- Video converters (HandBrake, FFmpeg GUIs)
- Media servers (Plex, Jellyfin)
- Subtitle editors
- Video downloaders (yt-dlp GUIs)
- Webcam tools
- Video quality analysis (QCTools)
- VFX review tools (DJV — also designGraphics)
- Video effects plugin marketplaces (FxFactory)
- Lossless video trimming (LosslessCut)
- Image-from-video extraction (SnapMotion)
- Privacy-focused video frontends (Yattee for YouTube)
- VLC companion tools (VLC Setup)

**Exclusion criteria**:
- NOT video conferencing (Zoom, Teams → communication)
- NOT game streaming/capture (game-specific tools → games)
- NOT audio-only tools → audioMusic
- NOT photo/image tools → designGraphics

**Tricky boundary cases**:
- **OBS**: Streaming AND recording software → videoMedia (not communication, even though it streams)
- **5KPlayer**: Plays video AND music — primarily a video player → videoMedia
- **Screenflick**: Screen recorder with audio — the screen recording is primary → videoMedia
- **DJV**: VFX image sequence viewer — designGraphics (primary) + videoMedia (secondary)

## games — Games

**Definition**: Games, game launchers (Steam, Epic), game console emulators, game-related tools (deck trackers, game trainers).

**Exclusion criteria**:
- NOT game controller/peripheral configuration → utilities
- NOT game development tools (Unity, Godot, Tiled, TexturePacker) → developerTools
- NOT JDK/SDK distributions → developerTools
- NOT terminal emulators → developerTools
- NOT calculator emulators (CEmu, HP Prime) → scienceEducation
- NOT Android emulators used for development (Genymotion) → developerTools
- NOT remote desktop tools → utilities

## securityPrivacy — Security & Privacy

**Definition**: VPNs, password managers, encryption, firewalls, antivirus, privacy tools, network security, ad blockers, 2FA/authenticators.

**Exclusion criteria**:
- NOT budgeting/finance apps → financeCrypto
- NOT crypto wallets → financeCrypto
- NOT digital signature tools → productivity
- NOT note-taking apps that happen to be "privacy-focused" → productivity
- NOT email clients that happen to be encrypted (Proton Mail → communication)
- NOT cloud storage that happens to be encrypted (Proton Drive → cloudStorage)

## financeCrypto — Finance & Crypto

**Definition**: Trading, banking, crypto wallets, accounting, invoicing, tax tools, budgeting, financial planning.

**Exclusion criteria**:
- NOT GPG/PGP encryption tools (cryptographic ≠ cryptocurrency) → securityPrivacy
- NOT Markdown editors → productivity
- NOT shopping apps → productivity
- NOT ad management tools → productivity

## cloudStorage — Cloud & Storage

**Definition**: Cloud storage/sync services (Dropbox, Google Drive, iCloud, OneDrive), NAS sync clients, WebDAV, cloud backup.

**STRICT inclusion**: Only apps whose PRIMARY purpose is storing/syncing files in the cloud or on a NAS.

**Exclusion criteria**:
- NOT remote desktop apps → utilities
- NOT SSH/SFTP clients → developerTools
- NOT download managers → utilities
- NOT torrent clients → utilities
- NOT printer/USB drivers → utilities
- NOT cloud CLI tools → developerTools
- NOT file transfer tools (P2P, LAN) → utilities
- NOT backup tools without cloud component → utilities

## scienceEducation — Science & Education

**Definition**: Scientific tools, calculators, education platforms, language learning, research tools, reference managers, astronomy, chemistry, math, GIS, electronic test equipment.

**Inclusion criteria**:
- Calculator emulators (CEmu, HP Prime, TI SmartView)
- Academic citation tools (Publish or Perish)
- Constraint modeling (MiniZinc)
- Molecular tools (wxMacMolPlt, MEGA)
- Educational programming (Scratch)
- Electronic test equipment (Waveforms by Digilent)
- Linguistic annotation (ELAN)
- Scientific graphing (SuperMJOGraph, Panoply)

## menuBar — Menu Bar

**Definition**: Apps whose PRIMARY purpose is providing a menu bar widget. The key question: "Would this app exist without the menu bar?" If no → menuBar. If yes → classify by its actual function.

**Inclusion criteria**:
- Menu bar managers (Bartender, Hidden Bar, Ice, Vanilla)
- Menu bar status indicators (AnyBar, SpaceID)
- Menu bar-only system monitors (Stats, eul, Fanny, MenuMeters)
- Menu bar-only calendars (Itsycal)
- Menu bar-only clocks/timezone tools (Clocker)
- Menu bar customization (SwiftBar, xbar)
- Menu bar notification tools (Gitify, MeetingBar)
- Battery indicators (Battery Buddy, CoconutBattery)
- Menu bar splitters/dividers (Menu Bar Splitter)

**Exclusion criteria — the "Would it exist without the menu bar?" test**:
- iStat Menus → menuBar (exists primarily as a menu bar widget)
- Bartender → menuBar (manages the menu bar itself)
- BUT: a full-featured app that also has a menu bar component is classified by its main function
- Apps that are menu bar utilities for another primary service classify by purpose

**Tricky boundary cases**:
- Apps like Claudebar (AI quota monitoring) or Codexbar (usage monitoring) are menuBar because their sole purpose is a status widget
- An app like MeetingBar is menuBar because the menu bar IS the product
- An app like Spotify would NOT be menuBar even though it has a menu bar presence — music is the purpose

## screensaverWallpaper — Screensaver & Wallpaper

**Definition**: Screensavers, wallpaper managers, live wallpapers, and visual display customization apps.

**Inclusion criteria**:
- Screensavers of any kind (clock, animation, web-based, retro)
- Wallpaper managers and auto-updaters (Bing Wallpaper, Pap.er)
- Live/dynamic wallpaper apps (Backdrop)
- Satellite/geographic wallpapers (Satellite Eyes)
- Trends/data visualizations designed for ambient display (Google Trends TV)

**Exclusion criteria**:
- NOT video players or editors → videoMedia
- NOT photo viewers/browsers → designGraphics
- NOT system utilities that happen to have a visual component → utilities

## ai — AI & LLMs (Trait Category — Always Secondary)

**Definition**: Apps with meaningful, user-facing AI or LLM functionality. This is a **trait category** — it is always assigned as a secondary category, never as a primary. Every AI app fundamentally *does* something (productivity, dev tools, design, etc.) and its primary category reflects that.

**Icon**: sparkle

**Inclusion criteria**:
- LLM clients and chat interfaces (ChatGPT, Claude, Ollama, LM Studio, GPT4All)
- AI code editors and assistants (Cursor, Windsurf, GitHub Copilot, Codeium)
- AI image generation and enhancement (Stable Diffusion, Topaz Photo AI, Upscayl)
- AI writing and translation tools (Grammarly, DeepL, LanguageTool)
- AI voice and transcription (Whisper variants, Krisp, Superwhisper)
- AI-enhanced productivity apps where AI is a significant, advertised feature (Notion AI, Raycast AI, Arc)
- AI video/audio editing (Descript, CapCut AI features)
- AI agents and frameworks (Claude Code, Codex, Agent TARS)
- AI search and knowledge tools (Perplexity, DevonThink AI)
- ML runtimes and model runners (MLX servers, AI benchmarks)

**Exclusion criteria**:
- NOT apps that use ML/AI internally without user-facing AI features (e.g., 1Password uses ML for autofill but AI is not a selling point)
- NOT apps where "AI" appears only in marketing copy without substantive AI functionality
- NOT apps where "ai" is part of the name but unrelated to artificial intelligence (e.g., Aircall, Airdash)

**Classification rule**: Always secondary. The primary category is determined by what the app primarily does:
- ChatGPT → productivity (primary) + ai (secondary)
- Cursor → developerTools (primary) + ai (secondary)
- Topaz Photo AI → designGraphics (primary) + ai (secondary)
- Krisp → utilities (primary) + ai (secondary)

## other — Other

**Definition**: Truly uncategorizable apps. Should have fewer than 10 apps. Always try another category first.
