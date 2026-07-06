---
name: cask-classifier
description: This skill should be used when the user asks to "classify casks", "review categories", "audit category assignments", "categorize new casks", "fix misclassified apps", "check which category a cask belongs to", "review Design & Graphics", or when verifying Homebrew cask categorization in CaskHub. Covers bulk category review, incremental classification of new casks, and correction of known misclassification patterns.
user-invocable: true
---

# CaskHub Cask Classifier

Systematic methodology for classifying macOS Homebrew casks into CaskHub's 15 categories. Prevents the known misclassification patterns discovered during the initial audit of 3,763 casks.

## When to Use

- Reviewing apps within a category for correctness
- Classifying newly added Homebrew casks
- Periodic audits of category accuracy
- Resolving ambiguous categorization decisions

## Core Principle: Classify by Purpose, Not Keywords

**Never keyword-match.** Always determine what the app's PRIMARY PURPOSE is by applying the classification tests below in order.

## The 5 Classification Tests (Apply in Order)

### Test 1: Known Name Recognition

Before anything else, check if the app is a well-known tool. R, Arduino, OBS, DevToys, GitUp, BlueJ — these are famous enough that name recognition overrides any keyword signal.

If the app is recognized, classify immediately. Do not let keyword signals override known identity.

### Test 2: The "Primary User" Test (Most Reliable)

Ask: **"Who opens this app and why?"**

| Primary User | Category |
|---|---|
| Software/hardware developer writing code | developerTools |
| Graphic/UI/UX/3D designer creating visual assets | designGraphics |
| System administrator, IT support, general user | utilities |
| Scientist, student, researcher, educator | scienceEducation |
| Writer, project manager, knowledge worker | productivity |
| Gamer playing games | games |
| Person watching/editing video | videoMedia |
| Person listening to/creating music | audioMusic |
| Person communicating with other people | communication |

### Test 3: The "Output" Test (For "Design" Ambiguity)

When the word "design" appears, check what the app produces:

| Output | Category | Example |
|---|---|---|
| Visual assets (images, icons, illustrations, mockups) | designGraphics | Figma, Sketch |
| Code, schemas, configs, PCB layouts | developerTools | KiCad, Bootstrap Studio |
| Documents, notes, tasks | productivity | Notion, Obsidian |
| Nothing visible (monitoring, system state) | utilities | iStatistica, gfxCardStatus |

### Test 4: Read the Homepage — Fetch It if Needed

First check the pre-fetched metadata (title, meta description) from `homepage_metadata.json`. Do NOT keyword-match — read it as a human sentence.

**If the metadata is missing, empty, or ambiguous, fetch the actual homepage URL** using WebFetch and read the page content. The homepage almost always states exactly what the app does in plain language.

This is critical — the pre-fetched metadata only captures `<title>` and `<meta>` tags, which are often generic or missing. The actual page body has the real description.

**Fallback: GitHub repo from download URL.** If the homepage is dead or unhelpful, query the Homebrew API for the cask's download URL:
```bash
curl -s "https://formulae.brew.sh/api/cask/<token>.json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url',''))"
```
If the download URL is a GitHub releases URL (e.g. `https://github.com/user/repo/releases/download/...`), strip the path after the repo name to get `https://github.com/user/repo`, then WebFetch that page. GitHub repo descriptions are reliable and almost never go offline.

Example: `moose` had a dead homepage (`getmoose.in`), but its download URL `https://github.com/ritz078/moose/releases/download/v0.6.2/moose-0.6.2-mac.zip` → repo `https://github.com/ritz078/moose` → revealed it's a torrent/media streaming app → utilities.

Examples of reading homepage content correctly:
- "R is a free software environment for statistical computing and graphics" → **statistical computing** is the purpose, "graphics" means data plots, not graphic design → developerTools
- "A Swiss Army knife for developers" → **developers** → developerTools
- "Graphical configurator for Dygma Raise keyboards" → **keyboard configurator** = hardware companion → utilities

### Test 5: Negative Keyword Awareness

These words are TRAPS that cause systematic misclassification:

| Trap Word | What It Usually Means | What Classifiers Think |
|---|---|---|
| "graphical" | "has a GUI" (not CLI) | Graphic design tool |
| "graphics" (in R, scientific tools) | Data visualization / charts | Graphic design |
| "design" (in EDA, SQL, web) | Engineering/schema/web design | Graphic design |
| "visual" (in IDE, programming) | Visual programming interface | Visual design |
| "emulator" | Could be calculator, dev, OR game | Always a game |
| "engine" | Could be game, search, or runtime | Always a game |
| "cloud" | Could be CLI, phone, monitoring | Cloud storage |
| "sync/remote/transfer" | Could be remote desktop, P2P | Cloud storage |

## Classification Workflow

### For Reviewing an Existing Category

1. Run the extraction script from the project root to list all apps in the category:
   ```bash
   python3 skills/cask-classifier/scripts/extract_category_apps.py --category <categoryId>
   ```

2. Go through EVERY app in the output. For each app:
   - Apply Test 1 (Known Name) — do you recognize this app?
   - Apply Test 2 (Primary User) — who opens this and why?
   - If ambiguous, apply Tests 3-5
   - If metadata is missing/vague OR classification is uncertain, **use WebFetch to load the cask's homepage URL** and read the actual page content. Do not guess — the homepage has the answer.

3. For each misclassification, record a correction:
   ```json
   {"token": "app-name", "was": "wrongCategory", "shouldBe": "rightCategory", "confidence": "high", "reason": "explanation"}
   ```

4. For apps that belong in multiple categories, record secondary additions:
   ```json
   {"token": "app-name", "action": "addSecondary", "secondary": ["category2"], "reason": "explanation"}
   ```

5. Save all corrections to `category_corrections.json` at the project root.

6. Present findings to the user for review before applying.

### For Classifying New Casks

1. For each new cask, gather: token, description, homepage URL
2. Fetch homepage metadata if not already in `homepage_metadata.json`
3. If description or metadata is vague, **use WebFetch to load the homepage URL** and read the page content — do not classify based on token name alone
4. Apply the 5 classification tests in order
5. Assign primary category; add secondary if clearly dual-purpose
6. If uncertain, flag for manual review

### Applying Corrections

After user approval, apply corrections from the project root:
```bash
python3 Scripts/apply_corrections.py --dry-run     # Preview first
python3 Scripts/apply_corrections.py --all         # Apply from category_corrections.json
```

Note: `category_corrections.json` must exist at the project root (generated during the review step above).

## Report Format

After every review session, produce a structured report:

```markdown
## Category Review: [Category Name]

**Apps reviewed**: N
**Corrections found**: N
**Pass rate**: X%

### Corrections

| Token | Was | Should Be | Reason |
|-------|-----|-----------|--------|
| app-name | designGraphics | developerTools | SQL database IDE |

### Secondary Category Additions

| Token | Primary (stays) | Add Secondary | Reason |
|-------|----------------|---------------|--------|
| app-name | designGraphics | developerTools | Design-to-code tool |

### Uncertain (Flagged for Manual Review)

| Token | Current | Description | Notes |
|-------|---------|-------------|-------|
| app-name | designGraphics | No clear description | Unknown app |
```

## Category Quick-Reference

For full definitions with boundary rules, consult **`references/category-definitions.md`**.

For the complete anti-pattern catalog and classification rules, consult **`references/classification-rules.md`**.

| ID | Name | One-Line Rule |
|----|------|--------------|
| developerTools | Developer Tools | User writes/ships code or manages infrastructure |
| browsers | Browsers | ONLY actual web browsers for browsing the internet |
| communication | Communication | Person-to-person messaging, calls, email, social |
| productivity | Productivity | Notes, tasks, writing, AI assistants, RSS, PDF editing |
| officeTools | Office Tools | Office suites, document editors (LibreOffice, MS Office, WPS) |
| utilities | Utilities | System tools, drivers, file managers, remote desktop |
| designGraphics | Design & Graphics | Output is visual assets: images, icons, 3D, UI mockups |
| audioMusic | Audio & Music | Creating, editing, or playing music/audio |
| videoMedia | Video & Media | Playing, editing, recording, or streaming video |
| games | Games | Playing games, game launchers, game console emulators |
| securityPrivacy | Security & Privacy | VPNs, passwords, encryption, firewalls, antivirus |
| financeCrypto | Finance & Crypto | Trading, banking, crypto wallets, accounting, tax |
| cloudStorage | Cloud & Storage | Cloud sync/storage services (Dropbox, Drive, Nextcloud) |
| scienceEducation | Science & Education | Scientific tools, calculators, education, research |
| menuBar | Menu Bar | PRIMARY purpose is providing a menu bar widget |
| screensaverWallpaper | Screensaver & Wallpaper | Screensavers, wallpaper managers, live wallpapers |
| other | Other | Truly uncategorizable (should have <10 apps) |

## Critical Boundary Rules

- **AI chatbots/LLM clients** → productivity (NOT communication)
- **SSH/SFTP clients** → developerTools (NOT cloudStorage)
- **Remote desktop apps** → utilities (NOT cloudStorage)
- **Download managers / torrent clients** → utilities (NOT cloudStorage)
- **Cloud CLI tools** (gcloud, aws-cli) → developerTools (NOT cloudStorage)
- **Game controller/peripheral software** → utilities (NOT games)
- **Game engines/dev tools** (Unity, Godot, Tiled) → developerTools (NOT games)
- **JDK distributions** → developerTools (NOT games)
- **Terminal emulators** → developerTools (NOT games)
- **Calculator emulators** → scienceEducation (NOT games)
- **Digital signature / e-signing tools** → productivity (NOT securityPrivacy)
- **Screen recorders & screen sharing/mirroring** → utilities (NOT videoMedia)
- **Keyboard layouts / input methods** → utilities
- **Hardware companion/config software** → utilities
- **Printer/USB/serial drivers** → utilities
- **"Design" in EDA/SQL/web context** → developerTools (NOT designGraphics)
- **"Graphical" meaning "has a GUI"** → does NOT mean designGraphics
- **Office suites** (LibreOffice, MS Office, WPS, ONLYOFFICE) → officeTools (NOT productivity)
- **"Virtual office" remote work tools** (Tandem, Roam) → productivity (NOT officeTools)
- **Screensavers and wallpaper apps** → screensaverWallpaper (NOT videoMedia or utilities)
- **Video conferencing apps** (Zoom, Teams, Meet, Jitsi) → communication (NOT videoMedia)
