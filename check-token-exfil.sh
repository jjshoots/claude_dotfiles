#!/bin/sh
# Is anything other than Claude Code spending my Claude tokens?
# Read-only. Prints no secrets. Run: sh ~/.claude/check-token-exfil.sh
echo "== 1. env overrides (how a resale proxy actually hijacks you) =="
for v in ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY \
         ANTHROPIC_CUSTOM_HEADERS HTTPS_PROXY HTTP_PROXY ALL_PROXY NODE_EXTRA_CA_CERTS; do
  eval "val=\$$v"
  [ -n "$val" ] && echo "  !! SET  $v" || echo "  ok     $v unset"
done

echo "\n== 2. same overrides hidden in settings.json (env / apiKeyHelper) =="
for f in "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" \
         "./.claude/settings.json" "./.claude/settings.local.json"; do
  [ -f "$f" ] || continue
  python3 -c "import json;d=json.load(open('$f'));e=d.get('env',{});k=d.get('apiKeyHelper');print('  $f -> env=%s apiKeyHelper=%s'%(e or '{}',k))" 2>/dev/null
done

echo "\n== 3. every process holding a connection to Anthropic =="
echo "   (each row must be a 'claude' process you started)"
lsof -nP -i TCP -sTCP:ESTABLISHED 2>/dev/null | awk 'NR>1{print $2}' | sort -u | while read p; do
  peer=$(lsof -nP -a -p "$p" -i TCP -sTCP:ESTABLISHED 2>/dev/null | awk 'NR>1{split($9,a,">");print a[2]}' | cut -d: -f1 | sort -u)
  for ip in $peer; do
    case "$ip" in 160.79.10*|160.79.11*)
      echo "  pid $p -> $ip : $(ps -o comm= -p $p)" ;;
    esac
  done
done

echo "\n== 4. credential store =="
security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 \
  && echo "  keychain entry present (normal)" || echo "  no keychain entry"
[ -f "$HOME/.claude/.credentials.json" ] && echo "  !! plaintext creds on disk: ~/.claude/.credentials.json" \
  || echo "  ok  no plaintext creds file"

echo "\n== 5. persistence that could run claude behind your back =="
crontab -l 2>/dev/null | grep -i claude && echo "  ^^ cron hit" || echo "  ok  no claude in crontab"
ls "$HOME/Library/LaunchAgents" 2>/dev/null | grep -i claude && echo "  ^^ launch agent hit" || echo "  ok  no claude LaunchAgent"

echo "\n== 6. MCP servers (each spawns a process) =="
python3 -c "
import json,os
p=os.path.expanduser('~/.claude.json')
d=json.load(open(p))
s=dict(d.get('mcpServers',{}))
for pr in d.get('projects',{}).values(): s.update(pr.get('mcpServers',{}))
[print('  ',k,':',v.get('command',v.get('url','?'))) for k,v in s.items()]
" 2>/dev/null

echo "\n== 7. where your tokens went, from your own transcripts (last 2 days) =="
python3 -c "
import json,glob,os,time,collections
cut=time.time()-2*86400; per=collections.Counter()
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
    if os.path.getmtime(f)<cut: continue
    t=0
    for line in open(f,errors='ignore'):
        try: u=(json.loads(line).get('message') or {}).get('usage') or {}
        except Exception: continue
        t+=sum(u.get(k,0) or 0 for k in ('input_tokens','output_tokens','cache_creation_input_tokens','cache_read_input_tokens'))
    if t: per[os.path.basename(os.path.dirname(f))+'/'+os.path.basename(f)[:8]]=t
for k,v in per.most_common(12): print(f'  {v:>15,}  {k}')
print(f'  {sum(per.values()):>15,}  TOTAL')
" 2>/dev/null
