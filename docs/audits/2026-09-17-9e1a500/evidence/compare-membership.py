from pathlib import Path
import subprocess,json
paths=['Tidy.xcodeproj/project.pbxproj','/private/tmp/tidy-audit-9e1a500-generated/Tidy.xcodeproj/project.pbxproj']
def memberships(path):
 d=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',path])); o=d['objects']; out={}
 for obj in o.values():
  if obj.get('isa')!='PBXNativeTarget':continue
  for phase in obj.get('buildPhases',[]):
   ph=o[phase]
   if ph['isa'] not in ['PBXSourcesBuildPhase','PBXResourcesBuildPhase']: continue
   out[(obj['name'],ph['isa'])]=set(o[o[f]['fileRef']].get('path','') for f in ph.get('files',[]) if 'fileRef' in o[f])
 return out
old,new=map(memberships,paths)
for key in sorted(old):
 print(key,'removed=',sorted(old[key]-new.get(key,set())),'added=',sorted(new.get(key,set())-old[key]))
