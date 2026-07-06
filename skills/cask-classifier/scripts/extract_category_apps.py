#!/usr/bin/env python3
"""
CaskHub Category App Extractor
================================
Extracts all apps in a given category (or all categories) with full metadata
for review. Supports multiple output formats.

Usage:
    python3 extract_category_apps.py --category designGraphics
    python3 extract_category_apps.py --category all --format summary
    python3 extract_category_apps.py --unclassified
    python3 extract_category_apps.py --category games --format json
"""
import json
import os
import sys
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(SCRIPT_DIR)))
CATEGORIES_PATH = os.path.join(PROJECT_DIR, "CaskHub", "Resources", "categories.json")
CASKS_PATH = os.path.join(PROJECT_DIR, "filtered_casks.json")
METADATA_PATH = os.path.join(PROJECT_DIR, "homepage_metadata.json")


def load_data():
    with open(CATEGORIES_PATH) as f:
        cat_data = json.load(f)
    with open(CASKS_PATH) as f:
        casks = json.load(f)
    cask_map = {c["token"]: c for c in casks}

    metadata = {}
    if os.path.exists(METADATA_PATH):
        with open(METADATA_PATH) as f:
            for item in json.load(f):
                metadata[item["token"]] = item

    return cat_data, cask_map, metadata


def get_category_apps(cat_data, category_id):
    """Return list of tokens in a category."""
    tc = cat_data["tokenToCategory"]
    apps = []
    for token, mapping in tc.items():
        cat = mapping["primary"] if isinstance(mapping, dict) else mapping
        if cat == category_id:
            apps.append(token)
    return sorted(apps)


def get_unclassified(cat_data, cask_map):
    """Return casks that exist in filtered_casks but not in categories."""
    tc = cat_data["tokenToCategory"]
    unclassified = []
    for token in cask_map:
        if token not in tc:
            unclassified.append(token)
    return sorted(unclassified)


def format_app(token, cask_map, metadata, verbose=True):
    """Format a single app's info for review."""
    cask = cask_map.get(token, {})
    meta = metadata.get(token, {})
    desc = (cask.get("desc") or "")[:120]
    hp = cask.get("homepage", "")
    title = (meta.get("title") or "")[:100]
    mdesc = (meta.get("meta_desc") or meta.get("og_desc") or "")[:150]

    if verbose:
        lines = [f"  {token}"]
        if desc:
            lines.append(f"    Desc: {desc}")
        if title:
            lines.append(f"    HP Title: {title}")
        if mdesc:
            lines.append(f"    HP Meta: {mdesc}")
        if hp and not title and not mdesc:
            lines.append(f"    Homepage: {hp}")
        return "\n".join(lines)
    else:
        return f"  {token} | {desc} | {title}"


def main():
    parser = argparse.ArgumentParser(description="Extract CaskHub category apps for review")
    parser.add_argument("--category", "-c", help="Category ID to extract (or 'all' for summary)")
    parser.add_argument("--unclassified", "-u", action="store_true", help="Show unclassified casks")
    parser.add_argument("--format", "-f", choices=["verbose", "compact", "json", "summary"],
                        default="verbose", help="Output format")
    args = parser.parse_args()

    cat_data, cask_map, metadata = load_data()
    categories = cat_data["categories"]

    if args.unclassified:
        unclassified = get_unclassified(cat_data, cask_map)
        print(f"=== UNCLASSIFIED CASKS ({len(unclassified)}) ===\n")
        for token in unclassified:
            print(format_app(token, cask_map, metadata, verbose=(args.format == "verbose")))
            if args.format == "verbose":
                print()
        return

    if not args.category:
        # Show distribution
        tc = cat_data["tokenToCategory"]
        dist = {}
        for mapping in tc.values():
            cat = mapping["primary"] if isinstance(mapping, dict) else mapping
            dist[cat] = dist.get(cat, 0) + 1

        print("=== CATEGORY DISTRIBUTION ===\n")
        for cat_id in sorted(dist, key=dist.get, reverse=True):
            name = categories.get(cat_id, {}).get("displayName", cat_id)
            print(f"  {name} ({cat_id}): {dist[cat_id]}")
        print(f"\n  Total: {sum(dist.values())}")
        return

    if args.category == "all":
        tc = cat_data["tokenToCategory"]
        dist = {}
        for mapping in tc.values():
            cat = mapping["primary"] if isinstance(mapping, dict) else mapping
            dist[cat] = dist.get(cat, 0) + 1

        for cat_id in sorted(dist, key=dist.get, reverse=True):
            name = categories.get(cat_id, {}).get("displayName", cat_id)
            apps = get_category_apps(cat_data, cat_id)
            print(f"=== {name} ({len(apps)} apps) ===\n")
            for token in apps:
                print(format_app(token, cask_map, metadata, verbose=False))
            print()
        return

    # Single category
    cat_id = args.category
    if cat_id not in categories:
        print(f"Error: Unknown category '{cat_id}'")
        print(f"Available: {', '.join(sorted(categories.keys()))}")
        sys.exit(1)

    apps = get_category_apps(cat_data, cat_id)
    name = categories[cat_id]["displayName"]
    print(f"=== {name} ({len(apps)} apps) ===\n")

    if args.format == "json":
        output = []
        for token in apps:
            cask = cask_map.get(token, {})
            meta = metadata.get(token, {})
            output.append({
                "token": token,
                "desc": cask.get("desc") or "",
                "homepage": cask.get("homepage", ""),
                "hpTitle": (meta.get("title") or "")[:100],
                "hpMeta": (meta.get("meta_desc") or meta.get("og_desc") or "")[:150],
            })
        print(json.dumps(output, indent=2, ensure_ascii=False))
    elif args.format == "compact":
        for token in apps:
            print(format_app(token, cask_map, metadata, verbose=False))
    else:
        for token in apps:
            print(format_app(token, cask_map, metadata, verbose=True))
            print()


if __name__ == "__main__":
    main()
