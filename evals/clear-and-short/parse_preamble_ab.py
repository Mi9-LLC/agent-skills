import json,sys,glob,os
for f in sorted(glob.glob(sys.argv[1]+"/*.jsonl")):
    print("=====",os.path.basename(f))
    for line in open(f,encoding="utf-8"):
        try: d=json.loads(line)
        except: continue
        if d.get("type")!="assistant": continue
        m=d["message"]; model=m.get("model")
        for c in m.get("content",[]):
            if c["type"]=="text": print(f"[{model}] TEXT: {c['text'][:300]!r}")
            elif c["type"]=="tool_use": print(f"  tool_use: {c['name']} {json.dumps(c['input'])[:100]}")
