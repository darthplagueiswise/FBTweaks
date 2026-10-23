#!/usr/bin/env python3
"""Extract four Facebook iOS Mach-O images from the exact IPA without modifying it."""
import argparse,hashlib,json,os,plistlib,struct,zipfile
from pathlib import Path
ROOT="Payload/Facebook.app/"
ITEMS={"main":"Facebook","shared":"Frameworks/FBSharedFramework.framework/FBSharedFramework",
"rare":"Frameworks/FBRarelyUsedFramework.framework/FBRarelyUsedFramework",
"rn":"Frameworks/FBReactNativeProductsFramework.framework/FBReactNativeProductsFramework"}
def sha(path):
    with open(path,"rb") as f:return hashlib.file_digest(f,"sha256").hexdigest()
def macho(path):
    with open(path,"rb") as f:
        h=f.read(32)
        if len(h)!=32 or h[:4]!=b"\xcf\xfa\xed\xfe":raise ValueError("Not a thin 64-bit Mach-O: "+str(path))
        _,cpu,subtype,_,count,size,_,_=struct.unpack("<8I",h)
        if count>250000 or size>128*1024*1024:raise ValueError("Invalid load commands")
        cmds=f.read(size)
    at=0;uuid=None
    for _ in range(count):
        if at+8>len(cmds):break
        cmd,length=struct.unpack_from("<II",cmds,at)
        if length<8 or at+length>len(cmds):break
        if cmd==0x1b and length>=24:
            h=cmds[at+8:at+24].hex()
            uuid="-".join((h[:8],h[8:12],h[12:16],h[16:20],h[20:]))
        at+=length
    return dict(uuid=uuid,cpu=hex(cpu),subtype=hex(subtype))
def extract(ipa,workdir,expected=None):
    ipa=Path(ipa).expanduser().resolve(strict=True)
    fingerprint=sha(ipa)
    if expected and fingerprint!=expected.lower():raise ValueError("IPA SHA256 mismatch: "+fingerprint)
    out=Path(workdir).expanduser().resolve()/fingerprint
    report={"ipa_sha256":fingerprint,"files":{}}
    with zipfile.ZipFile(ipa) as z:
        plist=plistlib.loads(z.read(ROOT+"Info.plist"))
        report["bundle"]={k:plist.get(k) for k in ("CFBundleIdentifier","CFBundleVersion","CFBundleShortVersionString","MinimumOSVersion")}
        for alias,path in ITEMS.items():
            item=z.getinfo(ROOT+path)
            if item.is_dir() or ((item.external_attr>>16)&0o170000)==0o120000:raise ValueError("Unexpected ZIP entry: "+path)
            out.mkdir(parents=True,exist_ok=True)
            temp=out/(alias+".tmp");dest=out/alias
            with z.open(item) as src,open(temp,"wb") as dst:
                while chunk:=src.read(1024*1024):dst.write(chunk)
            os.replace(temp,dest)
            report["files"][alias]=dict(path=str(dest),sha256=sha(dest),size=dest.stat().st_size,**macho(dest))
    (out/"manifest.json").write_text(json.dumps(report,indent=2)+"\n")
    return out,report
if __name__=="__main__":
    a=argparse.ArgumentParser()
    a.add_argument("ipa");a.add_argument("--workdir",default="scratch/rea-analysis/inputs")
    a.add_argument("--expected-sha256")
    v=a.parse_args();out,report=extract(v.ipa,v.workdir,v.expected_sha256)
    print(json.dumps(dict(directory=str(out),**report),indent=2))
