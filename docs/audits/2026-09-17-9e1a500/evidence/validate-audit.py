from pathlib import Path
import re,json,subprocess,hashlib,datetime
b=Path(__file__).resolve().parent.parent; repo=b.parents[2]
required=['audit-report.md','coverage-ledger.md','findings.md','evidence-manifest.md','remediation-plan.md','acceptance-gates.md']
for name in required:
 p=b/name;assert p.exists() and len(p.read_text())>1000,name
ledger=(b/'coverage-ledger.md').read_text();report=(b/'audit-report.md').read_text()
for i in range(1,17):assert f'|S{i:02}|' in ledger
for i in range(1,25):assert f'|T{i:02}|' in ledger
for i in range(1,21):assert f'|D{i:02} ' in report
for i in range(1,16):assert f'|C{i:02} ' in ledger
checkboxes=re.findall(r'^\| T\d{2}\.\d{3} \|',ledger,re.M);assert len(checkboxes)==165,len(checkboxes)
inv=json.loads((b/'evidence/runtime-inventory.log').read_text());assert len(inv['catalog'])==97;assert len(inv['registry'])==128
for row in inv['catalog']:assert '`'+row['id']+'`' in ledger
for row in inv['registry']:assert '`'+row+'`' in ledger
for p in b.rglob('*.md'):
 text=p.read_text();assert '/Users/mac/' not in text,p
 for label,link in re.findall(r'\[([^\]]*)\]\(([^)]+)\)',text):
  if link.startswith(('https:','http:','#')):continue
  dest=link.split('#')[0]
  if not dest:continue
  assert (p.parent/dest).exists(),(str(p),link)
 assert not any(line.rstrip()!=line for line in text.splitlines()),('trailing whitespace',str(p))
assert subprocess.run(['git','diff','--quiet'],cwd=repo).returncode==0,'primary tracked diff'
assert subprocess.run(['git','diff','--cached','--quiet'],cwd=repo).returncode==0,'staged tracked diff'
patterns=re.compile(r'binjamshid|albayyan|claude\.ai|/Users/[A-Za-z]',re.I)
count=0
for folder in ['Tidy','TidyCore/Sources']:
 for p in (repo/folder).rglob('*'):
  if not p.is_file():continue
  try: text=p.read_text()
  except (UnicodeError,OSError):continue
  count+=len(patterns.findall(text))
assert count==0,('personal source pattern matches',count)
print(json.dumps({'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'required_deliverables':len(required),'dimensions':20,'safety_requirements':16,'work_packages':24,'plan_checkbox_rows':len(checkboxes),'catalog_rows':len(inv['catalog']),'compiled_registry_rows':len(inv['registry']),'combined_scenarios':15,'primary_tracked_diff':'empty','source_personal_pattern_matches':count,'local_markdown_links':'valid','trailing_whitespace':'none'},indent=2))
