#!/usr/bin/env python3
# Run: python3 extract-fact-record.py <item.json> <tracker-pack.yaml> <out-fact-record.yaml> <out-sanitized-spec.md>
"""A fixture intake extractor: the interface a platform pack's extractor has,
with fixed rules of its own, so the authoring checker's suite runs against a
pack that names no platform.

  design source     a link on the host design.example
  component path    components/<name>/
  content an item   https://content.example/items/<id>; every cited id must
  may cite          be the item's own

Exit codes: 0 both files written; 1 an item with no key or type; 2 usage.
"""

import json
import re
import sys

URL_RE = re.compile(r"https?://[^\s)>\]]+")
DESIGN_URL_RE = re.compile(r"https?://design\.example/\S+")
CONTENT_URL_RE = re.compile(r"https?://content\.example/items/([\w-]+)")
COMPONENT_DIR_RE = re.compile(r"\bcomponents/[\w-]+/")


def flatten(node):
    if node is None:
        return ""
    if node.get("type") == "text":
        return node.get("text", "")
    inner = "".join(flatten(c) for c in node.get("content", []))
    return inner + "\n\n" if node.get("type") == "paragraph" else inner


def conventions(pack_yaml):
    lists = {}
    pattern = re.compile(r"^\s\s(\w+):\s\[(.*)\]$")
    with open(pack_yaml, encoding="utf-8") as f:
        for line in f:
            m = pattern.match(line.rstrip("\n"))
            if m:
                lists[m.group(1)] = [v.strip() for v in m.group(2).split(",") if v.strip()]
    return lists


def matches(text, words):
    return [w for w in words if re.search(r"\b" + re.escape(w) + r"\b", text, re.IGNORECASE)]


def yaml_list(values):
    return "[" + ", ".join(values) + "]"


def yaml_bool(value):
    return "true" if value else "false"


def main():
    if len(sys.argv) != 5:
        print("usage: extract-fact-record.py <item.json> <tracker-pack.yaml> "
              "<out-fact-record.yaml> <out-sanitized-spec.md>", file=sys.stderr)
        sys.exit(2)
    item_json, pack_yaml, out_facts, out_spec = sys.argv[1:5]
    with open(item_json, encoding="utf-8") as f:
        item = json.load(f)
    item_id = item.get("key")
    fields = item.get("fields") or {}
    item_type = (fields.get("issuetype") or {}).get("name")
    if not item_id or not item_type:
        print("error: the item has no key or no type", file=sys.stderr)
        sys.exit(1)

    summary = fields.get("summary") or ""
    description = flatten(fields.get("description")).strip()
    text = (summary + "\n\n" + description).strip()
    conv = conventions(pack_yaml)
    design = matches(text, conv.get("design_keywords", []))
    before = matches(text, conv.get("before_state_keywords", []))
    repro = matches(text, conv.get("reproduction_headings", []))
    accept = matches(text, conv.get("acceptance_criteria_headings", []))
    cited = CONTENT_URL_RE.findall(text)

    with open(out_facts, "w", encoding="utf-8") as f:
        f.write(f"item_id: \"{item_id}\"\n")
        f.write(f"item_type: {item_type}\n")
        f.write(f"labels: {yaml_list(fields.get('labels') or [])}\n")
        f.write(f"components: {yaml_list([c['name'] for c in fields.get('components') or []])}\n")
        f.write(f"files_named: {yaml_list(sorted(set(COMPONENT_DIR_RE.findall(text))))}\n")
        f.write("\n")
        f.write(f"design_source: {yaml_bool(DESIGN_URL_RE.search(text))}\n")
        f.write(f"design_mentioned: {yaml_bool(design)}\n")
        f.write("\n")
        f.write(f"has_description: {yaml_bool(description)}\n")
        f.write(f"has_acceptance_criteria: {yaml_bool(accept)}\n")
        f.write(f"has_reproduction_url: {yaml_bool(URL_RE.search(text))}\n")
        f.write(f"has_reproduction_steps: {yaml_bool(repro)}\n")
        f.write("\n")
        f.write(f"reproduction_content_ok: {yaml_bool(all(c == item_id for c in cited))}\n")
        f.write(f"before_state_mentioned: {yaml_bool(before)}\n")
        f.write("before_state_available: false\n")
    with open(out_spec, "w", encoding="utf-8") as f:
        f.write(f"# {summary}\n\nitem: {item_id} ({item_type})\n\n{description or '(no description)'}\n")

    print(f"item_id={item_id} item_type={item_type}")
    print("matched: design_keywords=" + (",".join(design) or "none")
          + " acceptance_criteria_headings=" + (",".join(accept) or "none"))


if __name__ == "__main__":
    main()
