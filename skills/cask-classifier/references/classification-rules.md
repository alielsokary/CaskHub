# Classification Rules and Anti-Patterns

Hard-won lessons from the CaskHub audit of 3,763 casks, where keyword-based classification produced 350+ errors that were manually corrected.

## The Golden Rule

**Classify by what the user DOES with the app, not by keywords in its description.**

A keyword-based approach will misclassify ~10% of apps. The human approach — "who opens this and why?" — catches what keywords miss.

## Anti-Pattern Catalog

### Anti-Pattern 1: "Design" Polysemy

The word "design" appears in many non-graphic-design contexts:

| Context | Example | Correct Category |
|---------|---------|-----------------|
| Electronics design | KiCad "electronics design automation" | developerTools |
| Database design | SQLEditor "SQL database design tool" | developerTools |
| Web design/development | Bootstrap Studio, RapidWeaver | developerTools (or dual) |
| API design | Anypoint Studio, Postman | developerTools |
| Motion/interaction design | Google Web Designer | designGraphics + developerTools |
| Level design | Tiled level editor | developerTools |

**Rule**: "Design" means designGraphics ONLY when the output is a visual asset. When the output is code, hardware, databases, or systems, it means developerTools.

### Anti-Pattern 2: "Graphical" ≠ "Graphics"

"Graphical" in a description almost always means "has a GUI" as opposed to being CLI-only:

| Description | What It Means | Correct Category |
|-------------|---------------|-----------------|
| "Graphical Java program for databases" | SQL client with a GUI | developerTools |
| "Graphical management tool" | K8s tool with a GUI | developerTools |
| "Graphical configurator" | Config tool with a GUI | utilities |
| "Graphical user interface for defaults" | macOS prefs tool | utilities |

**Rule**: "Graphical" describes the UI, not the domain. Ignore it for classification.

### Anti-Pattern 3: "Graphics" in Scientific Context

"Graphics" in the context of R, MATLAB, scientific tools means "data visualization / charts / plots":

| Description | What "Graphics" Means | Correct Category |
|-------------|----------------------|-----------------|
| R: "statistical computing and graphics" | R plots, ggplot2 charts | developerTools |
| "gfxCardStatus" | GPU hardware monitoring | utilities |
| Scientific visualization tools | 3D data rendering | scienceEducation |

**Rule**: Scientific/statistical "graphics" = data visualization, not graphic design.

### Anti-Pattern 4: "Visual" ≠ Visual Design

"Visual" in a programming/tool context means "visual interface for programming":

| App | "Visual" Means | Correct Category |
|-----|---------------|-----------------|
| FlutterFlow "visual development" | Drag-and-drop app builder | developerTools |
| Cables "visual programming" | Node-based WebGL coding | developerTools |
| Rivet "visual AI programming" | Node-based AI workflows | developerTools |
| Miro "visual collaboration" | Digital whiteboard | communication |
| Milanote "visual boards" | Creative project org | productivity |

**Rule**: "Visual" describes the interaction model, not the output type.

### Anti-Pattern 5: "Emulator" Ambiguity

"Emulator" matches game console emulators but also many non-game emulators:

| Emulator Type | Example | Correct Category |
|---|---|---|
| Game console | Dolphin, RetroArch, SNES9X | games |
| Calculator | CEmu (TI-84), HP Prime | scienceEducation |
| Android for development | Genymotion | developerTools |
| Android for gaming | MuMu, NoxPlayer | games |
| macOS VM | Vimy, Viables | utilities |

**Rule**: Check WHAT is being emulated, not just that it's an emulator.

### Anti-Pattern 6: "Cloud" Inflation

The word "cloud" attracted massive misclassification into cloudStorage:

| "Cloud" Context | Example | Correct Category |
|---|---|---|
| Cloud storage service | Dropbox, Google Drive | cloudStorage |
| Cloud CLI tool | gcloud-cli, aws-cli | developerTools |
| Cloud phone system | Cloud PBX | communication |
| Cloud monitoring | Cloudash (CloudWatch) | developerTools |
| Cloud FinOps | CloudPouch (AWS costs) | developerTools |

**Rule**: "Cloud" describes WHERE it runs, not WHAT it does.

### Anti-Pattern 7: Hardware Companion Misrouting

Hardware companion software gets misclassified based on the hardware's domain:

| Hardware | Companion App | Wrong Category | Correct Category |
|---|---|---|---|
| Gaming headset | ASTRO Command Center | games | utilities |
| Game controller | 8BitDo Software | games | utilities |
| Audio headset | Jabra Direct | audioMusic | utilities |
| Audio device | Bose Updater | audioMusic | utilities |
| Smart lights | Philips Hue Sync | cloudStorage | utilities |
| Keyboard | Bazecor (Dygma) | designGraphics | utilities |

**Rule**: Hardware companion/config software is ALWAYS utilities, regardless of what the hardware does.

## Rules for Secondary Categories

### The Decision Test

- **Primary**: What does this app primarily **do**? (the category most users would look for it in)
- **Secondary**: Who **else** would look for it? (the additional relevant category)

Criteria for adding a secondary category:
1. The app is actively used by people in BOTH domains
2. Both categories are a natural fit, not just "somewhat related"
3. The user explicitly identifies dual purpose

Examples of valid secondary categories:
- PaintCode: designGraphics (primary) + developerTools (secondary) — converts designs to code
- PixelSnap: designGraphics (primary) + developerTools (secondary) — used by both designers and devs
- Jandi: communication (primary) + productivity (secondary) — team chat with project management
- DJV: designGraphics (primary) + videoMedia (secondary) — VFX image sequences for film
- Wireshark: developerTools (primary) + utilities (secondary) — devs use it for debugging, sysadmins for network diagnostics
- Linear: developerTools (primary) + productivity (secondary) — a dev tool, but someone in Productivity might look for project management
- DeepL: productivity (primary) + ai (secondary) — a translator first, but also an AI-powered tool

Do NOT add secondary categories just because an app could theoretically be used in another domain.

### Trait Categories (Always Secondary)

Some categories describe a **trait or capability** that cuts across all other categories, rather than describing what the app primarily does. These categories are **always secondary, never primary**.

Currently, `ai` is the only trait category.

**Rules for trait categories:**
1. A trait category is never a valid primary — every app fundamentally *does* something (productivity, dev tools, design, etc.)
2. Add the trait as secondary when the app has **meaningful, user-facing** functionality in that trait
3. Do not add the trait just because the app uses the technology internally (e.g., every modern photo app uses ML, but that doesn't make it an AI app)

**AI trait examples:**
- ChatGPT: productivity (primary) + ai (secondary) — an AI chat client, but the user activity is productivity
- Cursor: developerTools (primary) + ai (secondary) — an IDE first, AI-powered
- Notion: productivity (primary) + ai (secondary) — a productivity app with AI features
- Topaz Photo AI: designGraphics (primary) + ai (secondary) — a photo tool powered by AI
- 1Password: securityPrivacy (primary), NO ai secondary — uses ML internally but AI is not a user-facing feature

## The Review Checklist

When reviewing a category, for each app ask:

1. **Do I recognize this app?** If yes, classify immediately from knowledge.
2. **Read the cask description as a sentence.** What does it say the app does?
3. **Read the homepage title/meta.** Does it confirm or change my understanding?
4. **Who is the primary user?** Developer? Designer? Sysadmin? Gamer?
5. **What does the app produce?** Code? Visual assets? Documents? System state?
6. **Am I being tricked by a keyword?** Check the anti-pattern catalog above.
7. **Is this hardware companion software?** → utilities, always.
8. **Is "design" being used in a non-graphic context?** → probably developerTools.

## When to Fetch the Homepage

The pre-fetched metadata (`homepage_metadata.json`) only contains `<title>` and `<meta>` tags. These are often:
- **Missing entirely** (~4% of casks had fetch errors)
- **Generic** (e.g., "GitHub - user/repo" tells you nothing about the app category)
- **Non-English** (Chinese, Japanese, Korean apps often have untranslated metadata)
- **Misleading** (marketing taglines instead of functional descriptions)

**Fetch the actual homepage (via WebFetch) when:**
1. The metadata title/description is empty or a generic GitHub page title
2. The cask description is vague (e.g., just "Visual programming tool")
3. The app is not recognized and could plausibly fit multiple categories
4. The trap keywords from Anti-Pattern 1-7 are present and need disambiguation

**Do NOT skip the homepage fetch to save time.** The R misclassification happened because the homepage clearly stated "statistical computing" but nobody read it. The homepage is the single most reliable source of truth for what an app does.

### Fallback Chain When Homepage Fails

When the homepage is dead, returns an error, or gives no useful info:

1. **Query the Homebrew API** to get the cask's download URL:
   ```
   https://formulae.brew.sh/api/cask/<token>.json → .url field
   ```

2. **Extract the GitHub repo** from the download URL. Many casks host releases on GitHub:
   - Download URL: `https://github.com/ritz078/moose/releases/download/v0.6.2/moose-0.6.2-mac.zip`
   - Extract repo: `https://github.com/ritz078/moose`
   - The pattern: strip everything after `/releases/`, `/archive/`, or `/raw/`

3. **WebFetch the GitHub repo page.** The repo description and README reliably describe what the app does.

4. If no GitHub URL exists, **try searching the web** for `"<app-name> macOS app"`.

**Real example:** `moose` was stuck in "other" because its homepage `getmoose.in` was dead and it had no description. The GitHub repo (`github.com/ritz078/moose`) revealed it's a torrent downloader and media streamer → **utilities**.

**Never leave an app as "uncertain" when the fallback chain hasn't been tried.** Dead homepages are not an excuse to skip classification — the download URL usually leads somewhere useful.

## Confidence Levels

- **high**: Clearly identifiable app, unambiguous category → apply automatically
- **medium**: Somewhat ambiguous, but evidence points one direction → flag for user review
- **uncertain**: Cannot determine with confidence → present to user with all available evidence

Only apply "high" confidence corrections automatically. Present "medium" and "uncertain" to the user.

## Periodic Audit Cadence

When new casks are added to Homebrew:

1. Compare `filtered_casks.json` against `categories.json` to find unclassified casks
2. Fetch homepage metadata for new casks
3. Classify each new cask using the 5 tests
4. Generate a report of new classifications for review
5. Apply after user approval
