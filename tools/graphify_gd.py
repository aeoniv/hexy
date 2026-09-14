"""GDScript extractor for graphify.

graphify has no tree-sitter grammar for .gd, so the Godot side of Hexy was
invisible to the graph. This walks scripts/ and tests/ with regexes and emits
nodes/edges in graphify's AST schema, plus `references` edges from GDScript
call sites (`_plugin.call("q6_step")`, `_android.call("chat")`) onto the
Kotlin @UsedByGodot methods already in the graph. It then merges into
graphify-out/graph.json, re-clusters, and regenerates html + report.

Run with the graphify interpreter:
  <graphify python> tools/graphify_gd.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from graphify.ids import normalize_id

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "graphify-out"

RE_CLASS = re.compile(r"^class_name\s+([A-Za-z_]\w*)", re.M)
RE_EXT = re.compile(r"^extends\s+([A-Za-z_]\w*)", re.M)
RE_FUNC = re.compile(r"^(?P<ind>[ \t]*)(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(", re.M)
RE_LOAD = re.compile(r"(?:preload|load)\(\"res://([^\"]+)\"\)")
RE_SIG = re.compile(r"^signal\s+([A-Za-z_]\w*)", re.M)
RE_QCALL = re.compile(r"\b([A-Z][A-Za-z0-9]*)\.([a-z_][a-z0-9_]*)\(")
RE_BARE = re.compile(r"(?<![\w.])([a-z_][a-z0-9_]*)\(")
RE_PLUG = re.compile(
    r"\b(_plugin|_android|plugin|_mesh|IxMnn|IxMesh)\.(?:call\(\"([a-z_0-9]+)\"|([a-z_0-9]+)\()"
)
BUILTIN = set(
    "print str int float len range min max abs clamp push_error push_warning assert "
    "is_instance_valid randf randi lerp round floor ceil sqrt pow sin cos exp log sign typeof "
    "is_zero_approx is_equal_approx preload load super emit_signal connect call call_deferred "
    "has_method has_signal queue_free add_child remove_child get_node get_tree set get new "
    "duplicate size append resize fill has keys values erase clear begins_with ends_with join "
    "split strip_edges to_lower to_upper format hash instantiate printerr deg_to_rad rad_to_deg "
    "wrapf wrapi fmod posmod snapped move_toward randfn seed randomize is_nan is_inf absf absi "
    "minf mini maxf maxi clampf clampi lerpf inverse_lerp remap ease smoothstep var_to_str "
    "str_to_var weakref tr set_process set_physics_process get_parent find_child get_child "
    "get_children get_child_count get_meta set_meta has_meta func".split()
)


def stem(rel: Path) -> str:
    return normalize_id("_".join(rel.with_suffix("").parts))


def main() -> None:
    graph = json.loads((OUT / "graph.json").read_text(encoding="utf-8"))
    known = {n["id"] for n in graph["nodes"]}
    files = sorted(
        p
        for d in ("scripts", "tests", "scenes", "addons")
        if (ROOT / d).exists()
        for p in (ROOT / d).rglob("*.gd")
    )

    # pass 1: symbols
    info: dict[str, dict] = {}
    class_to_file: dict[str, str] = {}
    func_index: dict[tuple[str, str], str] = {}
    for p in files:
        rel = p.relative_to(ROOT)
        s = stem(rel)
        src = p.read_text(encoding="utf-8", errors="replace")
        cls = RE_CLASS.search(src)
        funcs = []
        for m in RE_FUNC.finditer(src):
            ln = src.count("\n", 0, m.start()) + 1
            funcs.append((m.group(2), ln))
        info[rel.as_posix()] = dict(stem=s, src=src, cls=cls.group(1) if cls else None, funcs=funcs, lines=src.splitlines())
        if cls:
            class_to_file[cls.group(1)] = s
        for f, _ in funcs:
            func_index[(s, f)] = f"{s}_{normalize_id(f)}"

    nodes: list[dict] = []
    edges: list[dict] = []
    seen: set[str] = set()

    def node(nid, label, sf, loc=None, **kw):
        if nid in seen:
            return
        seen.add(nid)
        nodes.append(dict(id=nid, label=label, file_type="code", source_file=sf, source_location=loc, _origin="ast_gd", **kw))

    def edge(a, b, rel, sf, loc=None, ctx=None):
        if a == b:
            return
        edges.append(dict(source=a, target=b, relation=rel, confidence="EXTRACTED", confidence_score=1.0,
                          source_file=sf, source_location=loc, weight=1.0, _origin="ast_gd", context=ctx))

    kotlin: dict[str, str] = {}
    for nid in known:
        for api in ("ixmnn_ixmnn_", "ixmesh_ixmesh_"):
            if api in nid and "kotlin" in nid:
                kotlin.setdefault(nid.split(api, 1)[1], nid)

    bridge = 0
    for relp, d in info.items():
        s, src, funcs = d["stem"], d["src"], d["funcs"]
        node(s, Path(relp).name, relp)
        owner = s
        if d["cls"]:
            cid = f"{s}_{normalize_id(d['cls'])}"
            node(cid, d["cls"], relp, "L1", _callable=True, _callable_class=True)
            edge(s, cid, "contains", relp, "L1")
            owner = cid
        m = RE_EXT.search(src)
        if m and m.group(1) in class_to_file:
            ts = class_to_file[m.group(1)]
            edge(owner, f"{ts}_{normalize_id(m.group(1))}", "inherits", relp, "L%d" % (src.count("\n", 0, m.start()) + 1))
        for m in RE_LOAD.finditer(src):
            tgt = Path(m.group(1))
            if tgt.suffix == ".gd":
                edge(s, stem(tgt), "imports", relp, "L%d" % (src.count("\n", 0, m.start()) + 1))
        for m in RE_SIG.finditer(src):
            sid = f"{s}_{normalize_id(m.group(1))}"
            node(sid, f"signal {m.group(1)}", relp, "L%d" % (src.count("\n", 0, m.start()) + 1))
            edge(owner, sid, "defines", relp, ctx="signal")
        local = {f for f, _ in funcs}
        bounds = list(funcs) + [(None, len(d["lines"]) + 1)]
        for i, (f, ln) in enumerate(bounds[:-1]):
            fid = f"{s}_{normalize_id(f)}"
            node(fid, f"{f}()", relp, f"L{ln}", _callable=True)
            edge(owner, fid, "defines", relp, f"L{ln}", ctx="method")
            body = "\n".join(d["lines"][ln : bounds[i + 1][1] - 1])
            for mm in RE_QCALL.finditer(body):
                c, meth = mm.group(1), mm.group(2)
                if c in class_to_file:
                    ts = class_to_file[c]
                    if (ts, meth) in func_index:
                        edge(fid, func_index[(ts, meth)], "calls", relp, f"L{ln}")
                    else:
                        edge(fid, f"{ts}_{normalize_id(c)}", "references", relp, f"L{ln}")
            for mm in RE_BARE.finditer(body):
                n = mm.group(1)
                if n in local and n != f and n not in BUILTIN:
                    edge(fid, func_index[(s, n)], "calls", relp, f"L{ln}")
            for mm in RE_PLUG.finditer(body):
                meth = mm.group(2) or mm.group(3)
                if meth in kotlin:
                    edge(fid, kotlin[meth], "references", relp, f"L{ln}", ctx="godot_plugin_api")
                    bridge += 1
    # JNI binding: Kotlin `external fun x` <-> C++ `Java_<pkg>_<Class>_x`. Name mangling
    # is invisible to both ASTs. graphify drops cross-language calls/references as
    # phantoms, so this is emitted as `implements` (C++ symbol implements the Kotlin
    # external fun), which is exactly what JNI is.
    jni = 0
    src_of = {n["id"]: n.get("source_file") for n in graph["nodes"]}
    for nid in known:
        if "_kotlin_" not in nid or "native_" not in nid:
            continue
        head, _, meth = nid.rpartition("native_")
        for cid in known:
            if cid.endswith("native_" + meth) and "_cpp_" in cid and "_java_" in cid:
                edges.append(dict(source=cid, target=nid, relation="implements", confidence="EXTRACTED",
                                  confidence_score=1.0, source_file=src_of.get(cid), source_location=None, weight=1.0,
                                  _origin="ast_gd", context="jni_binding"))
                jni += 1
    # Kotlin lambda calls: `onWorker("") { IxMnnNative.nativeChat(...) }`. The Kotlin
    # AST drops calls nested inside lambda arguments, which is exactly how every
    # @UsedByGodot method reaches its JNI binding. Regex over fun bodies, same language.
    kt_calls = 0
    re_fun = re.compile(r"^\s*(?:(?:private|internal|public|override|suspend|inline)\s+)*fun\s+([A-Za-z_]\w*)\s*\(", re.M)
    re_cls = re.compile(r"^\s*(?:class|object)\s+([A-Za-z_]\w*)", re.M)
    re_nat = re.compile(r"\b(Ix\w+Native)\.([a-z]\w*)\(")
    for kt in (ROOT / "android_plugin").rglob("*.kt"):
        src = kt.read_text(encoding="utf-8", errors="replace")
        cm = re_cls.search(src)
        if not cm:
            continue
        rel = kt.relative_to(ROOT).as_posix()
        ks = stem(kt.relative_to(ROOT))
        funs = [(m.group(1), m.start()) for m in re_fun.finditer(src)] + [(None, len(src))]
        for (f, a), (_, b) in zip(funs, funs[1:]):
            fid = f"{ks}_{normalize_id(cm.group(1))}_{normalize_id(f)}"
            if fid not in known:
                continue
            for mm in re_nat.finditer(src[a:b]):
                tid = f"{ks.rsplit('_', 1)[0]}_{normalize_id(mm.group(1))}_{normalize_id(mm.group(1))}_{normalize_id(mm.group(2))}"
                if tid in known:
                    edges.append(dict(source=fid, target=tid, relation="calls", confidence="EXTRACTED", confidence_score=1.0,
                                      source_file=rel, source_location="L%d" % (src.count("\n", 0, a) + 1), weight=1.0,
                                      _origin="ast_gd", context="kotlin_lambda_call"))
                    kt_calls += 1
    print(f"GDScript: {len(files)} files, {len(nodes)} nodes, {len(edges)} edges, {bridge} plugin-bridge edges, {jni} JNI bindings, {kt_calls} Kotlin lambda calls")
    (OUT / ".graphify_gd.json").write_text(json.dumps(dict(nodes=nodes, edges=edges), indent=1), encoding="utf-8")

    # ---- merge into graph.json ----
    from graphify import report
    from graphify.analyze import god_nodes, suggest_questions, surprising_connections
    from graphify.build import build_from_json
    from graphify.cluster import cluster, label_communities_by_hub, remap_communities_to_previous, score_all
    from graphify.export import attach_hyperedges, to_json
    from graphify.exporters.html import to_html

    old = {n["id"]: n.get("community") for n in graph["nodes"] if n.get("community") is not None}
    old_labels = {int(k): v for k, v in json.loads((OUT / ".graphify_labels.json").read_text(encoding="utf-8")).items()}
    ext = dict(
        nodes=[n for n in graph["nodes"] if n.get("_origin") != "ast_gd"] + nodes,
        edges=[e for e in graph["links"] if e.get("_origin") != "ast_gd"] + edges,
        hyperedges=graph.get("hyperedges") or graph["graph"].get("hyperedges", []),
    )
    for n in ext["nodes"]:
        for k in ("community", "community_name"):
            n.pop(k, None)
    G = build_from_json(ext, root=ROOT)
    attach_hyperedges(G, ext["hyperedges"])
    comms = remap_communities_to_previous(cluster(G), old)
    hub = label_communities_by_hub(G, comms)
    labels = {}
    for cid, members in comms.items():
        keep = old_labels.get(cid)
        gd_share = sum(1 for m in members if G.nodes[m].get("_origin") == "ast_gd") / max(1, len(members))
        if keep and keep.startswith("Godot: ") and gd_share < 0.6:
            keep = None  # stale prefix from an earlier run
        if keep and gd_share < 0.6:
            labels[cid] = keep
        elif gd_share >= 0.6:
            labels[cid] = f"Godot: {hub.get(cid, cid)}"
        else:
            labels[cid] = str(hub.get(cid, cid))
    (OUT / ".graphify_labels.json").write_text(json.dumps({str(k): v for k, v in labels.items()}, indent=1), encoding="utf-8")
    commit = graph.get("built_at_commit")
    to_json(G, comms, str(OUT / "graph.json"), force=True, built_at_commit=commit, community_labels=labels)
    to_html(G, comms, str(OUT / "graph.html"), community_labels=labels)
    cost = json.loads((OUT / "cost.json").read_text(encoding="utf-8"))
    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    det = dict(total_files=len(manifest) + len(files), total_words=0)
    md = report.generate(
        G, comms, score_all(G, comms), labels, god_nodes(G), surprising_connections(G, comms), det,
        dict(input=cost["total_input_tokens"], output=cost["total_output_tokens"]), str(ROOT),
        suggested_questions=suggest_questions(G, comms, labels), built_at_commit=commit,
    )
    (OUT / "GRAPH_REPORT.md").write_text(md, encoding="utf-8")
    print(f"Graph: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, {len(comms)} communities")


if __name__ == "__main__":
    main()
