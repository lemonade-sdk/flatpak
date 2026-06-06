#!/usr/bin/env python3
import sys
import os
import json
import urllib.request
from pathlib import Path

def get_latest_commit(ref):
    url = f"https://api.github.com/repos/lemonade-sdk/lemonade/commits/{ref}"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "lemonade-flatpak-bumper"}
    )
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            return data['sha']
    except Exception as e:
        print(f"Error fetching ref '{ref}' from GitHub API: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    target_tag = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1].strip() else None
    ref = target_tag if target_tag else "main"

    print(f"Target ref: {ref}")
    new_commit = get_latest_commit(ref)
    print(f"Resolved commit SHA: {new_commit}")

    script_dir = Path(__file__).parent.resolve()
    manifest_path = script_dir.parent / "ai.lemonade_server.Lemonade.yaml"

    if not manifest_path.exists():
        print(f"Error: Manifest file not found at {manifest_path}", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path, 'r') as f:
        lines = f.readlines()

    source_idx = -1
    for i, line in enumerate(lines):
        if '&lemonade-source' in line:
            source_idx = i
            break

    if source_idx == -1:
        print("Error: Could not find &lemonade-source anchor in manifest", file=sys.stderr)
        sys.exit(1)

    source_indent = len(lines[source_idx]) - len(lines[source_idx].lstrip())

    block_lines_indices = []
    for i in range(source_idx + 1, len(lines)):
        line = lines[i]
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= source_indent:
            break
        block_lines_indices.append(i)

    if not block_lines_indices:
        print("Error: Empty &lemonade-source block", file=sys.stderr)
        sys.exit(1)

    old_commit = None
    old_tag = None

    for idx in block_lines_indices:
        stripped = lines[idx].strip()
        if stripped.startswith('commit:'):
            parts = stripped.split(':', 1)[1].split('#', 1)
            old_commit = parts[0].strip()
        elif stripped.startswith('tag:'):
            parts = stripped.split(':', 1)[1].split('#', 1)
            old_tag = parts[0].strip()

    print(f"Current commit in manifest: {old_commit}")
    print(f"Current tag in manifest: {old_tag}")

    changed = False
    if old_commit != new_commit or old_tag != target_tag:
        changed = True

    if changed:
        print("Changes detected. Updating manifest file...")
        first_block_line = lines[block_lines_indices[0]]
        block_indent = len(first_block_line) - len(first_block_line.lstrip())
        indent_str = ' ' * block_indent

        cleaned_block_lines = []
        for idx in block_lines_indices:
            line = lines[idx]
            stripped = line.strip()
            if stripped.startswith('commit:') or stripped.startswith('tag:'):
                continue
            cleaned_block_lines.append(line)

        new_lines_to_add = []
        if target_tag:
            new_lines_to_add.append(f"{indent_str}tag: {target_tag}\n")
            new_lines_to_add.append(f"{indent_str}commit: {new_commit}\n")
        else:
            new_lines_to_add.append(f"{indent_str}commit: {new_commit}  # main\n")

        url_idx = -1
        for i, line in enumerate(cleaned_block_lines):
            if line.strip().startswith('url:'):
                url_idx = i
                break

        if url_idx != -1:
            for offset, newline in enumerate(new_lines_to_add):
                cleaned_block_lines.insert(url_idx + 1 + offset, newline)
        else:
            cleaned_block_lines = new_lines_to_add + cleaned_block_lines

        start_slice = block_lines_indices[0]
        end_slice = block_lines_indices[-1] + 1
        lines[start_slice:end_slice] = cleaned_block_lines

        with open(manifest_path, 'w') as f:
            f.writelines(lines)
        print("Manifest file updated successfully.")
    else:
        print("No changes needed. Manifest is up to date.")

    compare_url = f"https://github.com/lemonade-sdk/lemonade/compare/{old_commit}...{new_commit}"
    print(f"Compare URL: {compare_url}")

    if 'GITHUB_OUTPUT' in os.environ:
        github_output = os.environ['GITHUB_OUTPUT']
        try:
            with open(github_output, 'a') as f:
                f.write(f"changed={str(changed).lower()}\n")
                f.write(f"old_commit={old_commit}\n")
                f.write(f"new_commit={new_commit}\n")
                f.write(f"compare_url={compare_url}\n")
                f.write(f"ref={target_tag if target_tag else new_commit[:7]}\n")
            print("Successfully wrote outputs to GITHUB_OUTPUT.")
        except Exception as e:
            print(f"Error writing to GITHUB_OUTPUT: {e}", file=sys.stderr)

if __name__ == '__main__':
    main()
