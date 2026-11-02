"""Generate offline keywords from pinned Schema, official XML and config samples.

Default: verify local source hashes and regenerate only completion/generated/.
--check: compare without writing. --download: restore pinned sources using curl.
No third-party Python dependencies; never modifies completion/custom/.
"""
import argparse
from datetime import datetime
import hashlib
import html.entities
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urldefrag, urljoin
import xml.etree.ElementTree as ET


def xml_text(element):
    return " ".join("".join(element.itertext()).split()) if element is not None else ""


def parse_xml(raw):
    # These trusted snapshots use DocBook/site entities. Do not fetch external DTDs.
    text = re.sub(r"&([A-Za-z][A-Za-z0-9._-]*);", lambda m:
                  m[0] if m[1] in ("amp", "lt", "gt", "quot", "apos") else
                  html.entities.html5.get(m[1] + ";", m[1]), raw)
    return ET.fromstring(text)


def schema_entries(documents, url):
    entries = {}
    cycles = set()

    def walk(node, path, document_url, active):
        if not isinstance(node, dict) or node.get("deprecated"):
            return
        if len(path) > 64:
            raise ValueError(f"Schema nesting exceeds 64 at {path}")
        if path and path[-1] not in ("*", "[]"):
            context = ".".join(path[:-1]).replace(".[]", "[]") or "$"
            key = (path[-1], context)
            entry = entries.setdefault(key, {"word": path[-1], "context": context,
                                            "description": "", "values": [], "type": []})
            if not entry["description"]:
                entry["description"] = node.get("description") or node.get("title") or ""
            kind = node.get("type", [])
            entry["type"] = sorted(set(entry["type"] + ([kind] if isinstance(kind, str) else kind)))
            values = node.get("enum", [node["const"]] if "const" in node else [])
            for value in values:
                if isinstance(value, (str, int, float, bool)) or value is None:
                    text = value if isinstance(value, str) else json.dumps(value)
                    if text not in entry["values"]:
                        entry["values"].append(text)
        if "$ref" in node:
            reference = urljoin(document_url, node["$ref"])
            target_url, fragment = urldefrag(reference)
            marker = (target_url, fragment)
            if marker in active:
                cycles.add(reference)
            else:
                if target_url not in documents:
                    raise ValueError(f"External $ref needs a pinned schema source: {reference}")
                target = documents[target_url]
                if fragment:
                    if not fragment.startswith("/"):
                        raise ValueError(f"Unsupported Schema anchor: {reference}")
                    for part in unquote(fragment[1:]).split("/"):
                        part = part.replace("~1", "/").replace("~0", "~")
                        target = target[int(part)] if isinstance(target, list) else target[part]
                walk(target, path, target_url, active | {marker})
        for name, child in node.get("properties", {}).items():
            walk(child, path + [name], document_url, active)
        for child in node.get("patternProperties", {}).values():
            walk(child, path + ["*"], document_url, active)
        additional = node.get("additionalProperties")
        if isinstance(additional, dict):
            walk(additional, path + ["*"], document_url, active)
        items = node.get("items")
        if isinstance(items, dict):
            walk(items, path + ["[]"], document_url, active)
        for branch in ("allOf", "anyOf", "oneOf", "prefixItems"):
            for child in node.get(branch, []):
                walk(child, path, document_url, active)

    walk(documents[url], [], url, set())
    for entry in entries.values():
        entry["source"] = url
        if not entry["description"]:
            entry["description"] = " / ".join(entry["type"]) or "配置字段"
    return list(entries.values()), sorted(cycles)


def nginx_entries(document):
    entries = []
    module = document.get("name", "").removeprefix("Module ")
    for directive in document.findall(".//directive"):
        text = xml_text(directive)
        if re.search(r"This (?:directive|functionality) is available as part of our commercial", text):
            continue
        name = directive.get("name")
        if not name:
            continue
        syntax = [name + " " + xml_text(s) for s in directive.findall("syntax")]
        description = xml_text(directive.find("para")).split("\n")[0]
        entries.append({
            "word": name, "context": ", ".join(xml_text(c) for c in directive.findall("context")),
            "module": module, "syntax": " | ".join(s.strip() for s in syntax),
            "description": description[:700], "version": xml_text(directive.find("appeared-in")),
            "source": "https://nginx.org" + document.get("link", "") + "#" + name,
        })
    return entries


def systemd_entries(document, filename):
    entries = []
    default_section = "Unit" if filename == "systemd.unit.xml" else "Service"

    def walk(element, section):
        if element.tag in ("refsect1", "refsect2", "refsect3"):
            title = xml_text(element.find("title"))
            if "[Install]" in title:
                section = "Install"
            elif "[Unit]" in title:
                section = "Unit"
        if element.tag == "varlistentry":
            names = [xml_text(v).split("=", 1)[0] for term in element.findall("term")
                     for v in term.findall("varname")]
            description = xml_text(element.find("./listitem/para"))
            if re.search(r"(?:deprecated|obsolete)", description, re.I):
                return
            versions = [e.get("xpointer", "")[1:] for e in
                        element.findall("./listitem/{http://www.w3.org/2001/XInclude}include")
                        if e.get("href") == "version-info.xml" and re.fullmatch(r"v\d+", e.get("xpointer", ""))]
            for name in names:
                if re.fullmatch(r"[A-Z][A-Za-z0-9]+", name):
                    entries.append({"word": name, "context": section,
                                    "description": description[:700], "version": ", ".join(versions),
                                    "source": "https://www.freedesktop.org/software/systemd/man/" +
                                    filename.removesuffix(".xml") + ".html#" + name + "="})
            return
        for child in element:
            walk(child, section)

    walk(document, default_section)
    for name, description in (("[Unit]", "单元说明与依赖"), ("[Service]", "服务进程与执行环境"),
                              ("[Install]", "启用时的安装关系")):
        if filename == "systemd.service.xml":
            entries.append({"word": name, "context": "section", "description": description})
    return entries


def tomcat_entries(document, source):
    entries = []
    component = source["component"]
    base = "https://tomcat.apache.org/tomcat-" + ".".join(source["ref"].split(".")[:2]) + "-doc/config/"
    link = base + document.get("url", Path(source["file"]).stem + ".html")
    module = "Tomcat " + source["ref"]
    elements = {component}

    def walk(element, owner, section):
        if element.tag in ("section", "subsection"):
            section = element.get("name", "")
            if "SSL Support - SSLHostConfig" in section:
                owner = "SSLHostConfig"
                elements.add(owner)
            elif "SSL Support - Certificate" in section:
                owner = "Certificate"
                elements.add(owner)
        if element.tag == "attribute":
            name = element.get("name", "")
            description = xml_text(element)
            if not re.fullmatch(r"[A-Za-z_:][A-Za-z0-9_.:-]*", name):
                return
            if re.search(r"This attribute (?:is|has been) deprecated", description, re.I):
                return
            entries.append({"word": name, "kind": "attribute", "context": owner + " / " + section,
                            "module": module, "version": source["ref"], "syntax": name + '=\"...\"',
                            "description": description[:700], "source": link})
            return
        for child in element:
            walk(child, owner, section)

    walk(document, component, "")
    description = xml_text(document.find("./body/section[@name='Introduction']/p"))
    for name in sorted(elements):
        entries.append({"word": name, "kind": "element", "context": "XML element", "module": module,
                        "version": source["ref"], "description": description[:700] if name == component else name + " TLS 配置元素",
                        "syntax": "<" + name + " ...>", "source": link})
    return entries


def redis_entries(text, registry, source):
    # Registry intersection prevents prose or Redis client commands becoming config keys.
    known = set(re.findall(r'create[A-Za-z]+Config\("([a-z][a-z0-9-]*)"', registry))
    known.update(re.findall(r'!strcasecmp\(argv\[0\],\s*"([a-z][a-z0-9-]*)"\)', registry))
    known.discard("sentinel")
    entries = {}
    section, comments = "redis", []
    prose = {"is", "are", "was", "were", "can", "will", "must", "should", "has", "have", "to", "of", "and", "with", "for"}
    for line in text.splitlines():
        heading = re.match(r"^#{3,}\s*([^#]+?)\s*#+$", line)
        if heading:
            section, comments = heading[1].strip(), []
            continue
        match = re.match(r"^\s*(#\s*)?([a-z][a-z0-9-]*)\s+(.+)$", line)
        if match and match[2] in known and match[3].split()[0] not in prose:
            name = match[2]
            entry = entries.setdefault(name, {"word": name, "context": section, "version": source["ref"],
                                              "description": " ".join(comments)[:700], "syntax": "",
                                              "source": source["url"], "samples": []})
            sample = name + " " + match[3].strip()
            if sample not in entry["samples"] and len(entry["samples"]) < 3:
                entry["samples"].append(sample)
            if not match[1]:
                comments = []
        elif line.lstrip().startswith("#"):
            comment = line.lstrip().lstrip("#").strip()
            if comment:
                comments.append(comment)
        elif line.strip():
            comments = []
    for entry in entries.values():
        entry["syntax"] = " | ".join(entry.pop("samples"))
        if not entry["description"]:
            entry["description"] = "Redis 配置指令，参数示例见语法"
    return list(entries.values())


def dockerd_help_entries(text, source):
    entries = []
    current = None
    for line in text.splitlines():
        match = re.match(r"^\s*(?:(-\w),\s*)?(--[a-z][a-z0-9-]*)(?:\s+(\S+))?\s{2,}(.+)$", line)
        if match:
            current = {"word": match[2], "context": "dockerd CLI", "version": source["ref"],
                       "description": match[4], "syntax": match[2] + (" " + match[3] if match[3] else ""),
                       "type": [match[3] or "boolean"], "source": source["url"]}
            if match[1]:
                current["shorthand"] = match[1]
            entries.append(current)
        elif current and line.startswith(" " * 10) and line.strip():
            current["description"] += " " + line.strip()
    if not entries:
        raise ValueError("No dockerd help options extracted")
    short = []
    for entry in entries:
        default = re.search(r"\(default (.+)\)$", entry["description"])
        if default:
            entry["default"] = default[1]
        for choice in re.findall(r"\(([^)]*\|[^)]*)\)", entry["description"]):
            entry["values"] = re.findall(r'"([^"\n]+)"', choice)
        alias = entry.pop("shorthand", None)
        if alias:
            short.append({**entry, "word": alias, "syntax": alias + " / " + entry["syntax"]})
            entry["description"] += "；短选项：" + alias
    return entries + short


def docker_daemon_entries(sources, help_entries):
    # A restricted reader for the pinned Go struct definitions, not a general Go parser.
    structs, aliases, origins = {}, {}, {}
    for source, text in sources:
        package = source["package"]
        for match in re.finditer(r"(?ms)^type (\w+) struct \{\n(.*?)^\}", text):
            key = package + "." + match[1]
            structs[key], origins[key] = match[2], source["url"]
        for name, target in re.findall(r"(?m)^type (\w+) = ([\w.]+)\s*$", text):
            aliases[package + "." + name] = target
    # These two types implement custom JSON decoding; their internal structs are not JSON fields.
    aliases.update({"opts.PoolsOpt": "[]ipamutils.NetworkToSplit", "config.BuilderGCFilter": "[]string"})
    help_by_word = {e["word"].removeprefix("--"): e for e in help_entries if e["word"].startswith("--")}
    json_to_flag = {
        "authorization-plugins": "authorization-plugin", "exec-opts": "exec-opt", "storage-opts": "storage-opt",
        "labels": "label", "hosts": "host", "log-opts": "log-opt", "dns-opts": "dns-opt",
        "registry-mirrors": "registry-mirror", "insecure-registries": "insecure-registry",
        "node-generic-resources": "node-generic-resource", "default-address-pools": "default-address-pool",
        "default-network-opts": "default-network-opt", "features": "feature", "runtimes": "add-runtime",
        "default-ulimits": "default-ulimit", "cdi-spec-dirs": "cdi-spec-dir",
        "containerd-plugin-namespace": "containerd-plugins-namespace",
    }
    entries = []

    def walk(go_type, path, package, active):
        go_type = go_type.lstrip("*")
        if go_type.startswith("[]"):
            walk(go_type[2:], path + ["[]"], package, active)
            return
        mapping = re.match(r"^map\[[^]]+\](.+)$", go_type)
        if mapping:
            walk(mapping[1], path + ["*"], package, active)
            return
        key = go_type if "." in go_type else package + "." + go_type
        if key in aliases:
            walk(aliases[key], path, package, active)
            return
        if key not in structs or key in active:
            return
        comments = []
        for line in structs[key].splitlines():
            line = line.strip()
            if line.startswith("//"):
                comments.append(line.removeprefix("//").strip())
                continue
            if not line:
                comments = []
                continue
            tag = re.search(r'`json:"([^" ,]*)(?:,[^" ]*)?"`', line)
            declaration = line.split("`", 1)[0].split("//", 1)[0].strip()
            parts = declaration.split(None, 1)
            if not parts:
                comments = []
                continue
            if len(parts) == 1 and not tag:
                walk(parts[0], path, key.split(".", 1)[0], active | {key})
                comments = []
                continue
            if not re.fullmatch(r"[A-Z]\w*", parts[0]):
                comments = []
                continue
            field = parts[0]
            field_type = parts[1].strip() if len(parts) == 2 else field
            name = tag[1] if tag and tag[1] else ({"GC": "gc"}.get(field, field[0].lower() + field[1:]))
            description = " ".join(comments)
            comments = []
            if name == "-" or "Deprecated:" in description or "Deprecated:" in line:
                continue
            flag = json_to_flag.get(name, name)
            # Do not advertise internal/hidden-only root fields merely because they have JSON tags.
            if not path and flag not in help_by_word and name not in ("builder", "proxies"):
                continue
            help_entry = help_by_word.get(flag)
            if help_entry:
                description += ("；" if description else "") + "相关 CLI --" + flag + "：" + help_entry["description"]
            context = ".".join(path).replace(".[]", "[]") or "$"
            simple = field_type.lstrip("*")
            if simple == "bool":
                kind = "boolean"
            elif simple == "string" or simple in ("net.IP", "netip.Prefix"):
                kind = "string"
            elif re.fullmatch(r"u?int\d*|float\d+", simple):
                kind = "number"
            elif simple.startswith("[]") or simple == "opts.PoolsOpt":
                kind = "array"
            elif simple.startswith("map[") or (key.split(".", 1)[0] + "." + simple) in structs:
                kind = "object"
            else:
                kind = "Go: " + simple
            entries.append({"word": name, "context": context, "type": [kind],
                            "description": description or "Moby Linux daemon 配置字段",
                            "version": "27.3.1 / Linux", "source": origins[key]})
            walk(field_type, path + [name], key.split(".", 1)[0], active | {key})

    if "config.Config" not in structs:
        raise ValueError("Missing Moby Linux config.Config definition")
    walk("config.Config", [], "config", set())
    return entries


def mdn_header_entries(text, source):
    """Read only the curated MDN HTTP header pages; do not evaluate MDN macros."""
    front = re.match(r"\A---\n(.*?)\n---\n", text, re.S)
    if not front:
        raise ValueError(f"Missing MDN front matter: {source['file']}")
    metadata = front[1]
    if re.search(r"(?m)^\s*- (?:deprecated|experimental)\s*$", metadata):
        return []
    name = source["header"]
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*", name):
        raise ValueError(f"Invalid HTTP header name: {name}")
    if not re.search(r"(?m)^slug: Web/HTTP/Reference/Headers/" + re.escape(name) + r"\s*$", metadata):
        raise ValueError(f"MDN header slug mismatch: {source['file']}")
    body = text[front.end():]

    def plain(value):
        value = re.sub(r"\{\{\w+\((.*?)\)\}\}", lambda m:
                       (re.findall(r'"([^"\n]*)"', m[1]) or [""])[-1], value)
        value = re.sub(r"\{\{[^}]+\}\}", "", value)
        value = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", value)
        value = re.sub(r"<[^>]+>", "", value)
        return " ".join(value.replace("**", "").replace("`", "").split())

    summary = next((plain(p) for p in body.split("\n\n")
                    if p.strip() and not p.lstrip().startswith(("{{", "<", ">", "#", "```"))), "")
    table = re.search(r'<th[^>]*>\s*Header type\s*</th>\s*<td[^>]*>(.*?)</td>', body, re.S)
    section = re.search(r"(?ms)^## Syntax\n(.*?)(?=^## |\Z)", body)
    syntax = []
    if section:
        for block in re.findall(r"```[^\n]*\n(.*?)```", section[1], re.S):
            for line in block.splitlines():
                if re.match(re.escape(name) + r"\s*:", line, re.I):
                    syntax.append(line.strip())
    nonstandard = re.search(r"(?m)^\s*- non-standard\s*$", metadata) or "{{Non-standard_header}}" in body
    return [{"word": name, "context": plain(table[1]) if table else "HTTP header",
             "module": "MDN Web Docs" + (" / 非标准" if nonstandard else ""),
             "description": summary[:800], "syntax": " | ".join(syntax[:6])[:1000],
             "version": "MDN content " + source["ref"][:12],
             "source": "https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/" + name}]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent / "completion"
    manifest = json.loads((root / "sources.json").read_text())
    documents = {}
    registries = {}
    go_sources, dockerd_help = [], []
    outputs = {name: [] for name in ("opencode", "compose", "nginx", "systemd-service", "tomcat", "redis", "dockerd-cli", "docker-daemon", "http-headers")}
    for item in manifest:
        folder = "licenses" if item["format"] == "license" else "sources"
        source = root / folder / item["file"]
        if args.download and not source.exists():
            if item["url"].startswith("local:"):
                raise ValueError(f"Local help snapshot must be supplied explicitly, not executed automatically: {source}")
            source.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["curl", "-fsSL", "--retry", "4", "--retry-all-errors",
                            "--connect-timeout", "30", "--max-time", "120",
                            "-o", str(source), item["url"]], check=True)
        actual = hashlib.sha256(source.read_bytes()).hexdigest()
        if actual != item["sha256"]:
            raise ValueError(f"{source}: SHA256 {actual} != {item['sha256']}")
        if item["format"] == "schema":
            documents[item["url"]] = json.loads(source.read_text())
        elif item["format"] == "redis-registry":
            registries[item["group"]] = source.read_text()
        elif item["format"] == "dockerd-go":
            go_sources.append((item, source.read_text()))
        elif item["format"] == "dockerd-help":
            dockerd_help = dockerd_help_entries(source.read_text(), item)
    cycles = {}
    for item in manifest:
        if item["format"] in ("license", "redis-registry", "dockerd-go", "dockerd-help", "dockerd-version", "mdn-header-index"):
            continue
        source = root / "sources" / item["file"]
        if item["format"] == "schema":
            entries, omitted = schema_entries(documents, item["url"])
            cycles[item["group"]] = omitted
        elif item["format"] == "nginx":
            entries = nginx_entries(parse_xml(source.read_text()))
        elif item["format"] == "systemd":
            entries = systemd_entries(parse_xml(source.read_text()), source.name)
        elif item["format"] == "tomcat":
            entries = tomcat_entries(parse_xml(source.read_text()), item)
        elif item["format"] == "redis":
            entries = redis_entries(source.read_text(), registries[item["group"]], item)
        elif item["format"] == "mdn-header":
            entries = mdn_header_entries(source.read_text(), item)
        else:
            raise ValueError(f"Unknown source format: {item['format']}")
        outputs[item["group"]].extend(entries)
    outputs["dockerd-cli"] = dockerd_help
    outputs["docker-daemon"] = docker_daemon_entries(go_sources, dockerd_help)
    for name, entries in outputs.items():
        unique = {(e["word"], e.get("context", ""), e.get("module", "")): e for e in entries}
        result = {
            "notice": "Extracted/reformatted from the cited upstream sources; not a validator. See ../licenses/.",
            "sources": [s for s in manifest if s["group"] == name],
            "omitted_recursive_refs": cycles.get(name, []),
            "entries": sorted(unique.values(), key=lambda e: (e["word"], e.get("context", ""), e.get("module", ""))),
        }
        content = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        dest = root / "generated" / (name + ".json")
        if args.check:
            if not dest.exists() or dest.read_text() != content:
                raise ValueError(f"{dest}: generated content differs; regenerate explicitly")
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.exists() and dest.read_text() != content:
                backup = dest.with_name("." + dest.name + ".regenerate-backup-" + datetime.now().strftime("%Y-%m-%d-%H-%M-%S"))
                backup.write_bytes(dest.read_bytes())
            dest.write_text(content)
        print(f"{name}: {len(unique)} entries, {len(result['omitted_recursive_refs'])} recursive refs omitted")


if __name__ == "__main__":
    main()
