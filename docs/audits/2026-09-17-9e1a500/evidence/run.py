import subprocess,sys,json,datetime,time,os
from pathlib import Path
base=Path(__file__).resolve().parent
label=sys.argv[1]; command=sys.argv[2:]
start=datetime.datetime.now(datetime.timezone.utc).isoformat(); t=time.monotonic()
p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
with (base/(label+".log")).open("w") as log:
    for line in p.stdout:
        log.write(line.replace(str(Path.home()),"<HOME>"));log.flush()
p.wait()
class Result: returncode=p.returncode
r=Result()
out=(base/(label+".log")).read_text()
meta={"command":command,"cwd":str(Path.cwd()).replace(str(Path.home()),"<HOME>"),"started_utc":start,"ended_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"seconds":round(time.monotonic()-t,3),"exit_code":r.returncode}
(base/(label+".json")).write_text(json.dumps(meta,indent=2).replace(str(Path.home()),"<HOME>")+"\n")
print(json.dumps(meta)); print(out[-4500:]);sys.exit(r.returncode)
