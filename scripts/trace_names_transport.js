/* NÃO EXECUTADO NO IPHONE. Observational hooks for the exact supplied build.
 * Does not change arguments, return values, requests, credentials or permissions.
 * Correlates at fetcher->SimpleCallbacks construction, never onStarted (RET here).
 * Emits allowlisted request metadata and sanitized response diagnostics only.
 */
'use strict';
function redact(text) {
  return String(text)
    .replace(/["']?(?:access_token|authorization|cookie|session_token)["']?\s*[:=]\s*(?:"[^"\r\n]*"|'[^'\r\n]*'|[^,;\r\n}]+)/gi,'[REDACTED]')
    .replace(/\bBearer\s+[A-Za-z0-9._~+\/-]+=*/gi,'[REDACTED]')
    .replace(/\bEAA[A-Za-z0-9_-]{15,}\b/g,'[REDACTED_TOKEN]')
    .replace(/https?:\/\/[^\s"']+/gi,'[REDACTED_URL]')
    .replace(/[\w.+-]+@[\w.-]+\.[a-z]{2,}/gi,'[REDACTED_EMAIL]')
    .replace(/\b[0-9a-f]{16,}\b/gi,'[REDACTED_ID]')
    .replace(/\b\d{6,}\b/g,'[REDACTED_ID]').slice(0,1024);
}
function responseInfo(bytes) {
  const out={body_bytes:bytes.length,server_body_source:'TigonSimpleCallbacks.onBody'};
  if(!bytes.length)return {...out,body_status:'not_delivered_to_observed_callback'};
  if(bytes[0]===31&&bytes[1]===139)return {...out,body_status:'gzip_not_decoded'};
  let text;
  try{text=decodeURIComponent(Array.from(bytes,b=>'%'+b.toString(16).padStart(2,'0')).join(''));}
  catch(_){return {...out,body_status:'non_utf8'};}
  if(/^(None|Cancel) domain: /.test(text))return {...out,body_status:'native_error_summary_NOT_server_JSON'};
  let d;try{d=JSON.parse(text);}catch(_){return {...out,body_status:'non_json_body'};}
  out.body_status='json';out.root_type=Array.isArray(d)?'array':typeof d;
  if(!d||typeof d!=='object')return out;
  out.id_to_names_is_array=Array.isArray(d.id_to_names);
  if(out.id_to_names_is_array)out.name_record_count=d.id_to_names.length;
  if(d.error&&typeof d.error==='object'){
    out.error={};
    for(const key of ['code','error_subcode','type','message']){
      const v=d.error[key];
      if(typeof v==='number'||typeof v==='boolean')out.error[key]=v;
      else if(typeof v==='string')out.error[key]=redact(v);
    }
  }
  return out;
}
function copyChain(head,maxBytes=2097152,maxSegments=256) {
  if(head.isNull())return new Uint8Array(0);
  const chunks=[],seen=new Set();let p=head,n=0;
  while(true){
    const key=p.toString();
    if(seen.has(key))throw Error('cycle_does_not_return_to_head');
    if(seen.size>=maxSegments)throw Error('segment_limit');
    seen.add(key);
    const len=Number(p.readU64().toString());
    if(!Number.isSafeInteger(len)||len<0||n+len>maxBytes)throw Error('body_limit');
    const data=p.add(8).readPointer();
    if(len){if(data.isNull())throw Error('null_data');chunks.push(new Uint8Array(data.readByteArray(len)));n+=len;}
    p=p.add(32).readPointer();
    if(p.equals(head))break;
    if(p.isNull())throw Error('broken_chain');
  }
  const out=new Uint8Array(n);let off=0;for(const c of chunks){out.set(c,off);off+=c.length;}return out;
}
function startObserver() {
  const m=Process.getModuleByName('FBSharedFramework');
  const uuidExpected='4c4c44fe55553144a1c26ccae4ed2597';
  let cursor=m.base.add(32),uuid=null;
  if(m.base.readU32()!==0xfeedfacf)throw Error('expected_MachO64');
  for(let n=0;n<m.base.add(16).readU32();n++){
    const cmd=cursor.readU32(),size=cursor.add(4).readU32();if(size<8||size>1048576)throw Error('load_command_invalid');
    if(cmd===0x1b)uuid=Array.from(new Uint8Array(cursor.add(8).readByteArray(16)),b=>b.toString(16).padStart(2,'0')).join('');
    cursor=cursor.add(size);
  }
  if(uuid!==uuidExpected)throw Error('module_UUID_mismatch');
  const sigs={"0xa17f70": "e6031eaaabc2d797", "0xa15ab4": "ff0302d1f65705a9", "0xfde218": "620000101f2003d5", "0xfde24c": "080c48f8480000b5", "0xfde27c": "ff0303d1f65709a9", "0x3fdda18": "082040f9480000b5"};
  for(const [va,hex] of Object.entries(sigs)){
    const got=Array.from(new Uint8Array(m.base.add(va).readByteArray(hex.length/2)),b=>b.toString(16).padStart(2,'0')).join('');
    if(got!==hex)throw Error('instruction_mismatch_'+va);
  }
  const active=new Map(),objects=new Map();let sequence=0;
  const emit=(event,data)=>send({event,time_utc:new Date().toISOString(),...data});
  function cppSize(p){
    const shortSize=p.add(23).readU8(),long=Boolean(shortSize&128);
    const n=long?Number(p.add(8).readU64().toString()):shortSize;
    if(!Number.isSafeInteger(n)||n<0||n>2097152)throw Error('string_size');
    return n;
  }
  function cppString(p){
    const shortSize=p.add(23).readU8(),long=Boolean(shortSize&128);
    const n=long?Number(p.add(8).readU64().toString()):shortSize;
    if(!Number.isSafeInteger(n)||n<0||n>2097152)throw Error('string_size');
    return n?(long?p.readPointer():p).readUtf8String(n):'';
  }
  const listeners=[];
  function hook(va,callbacks){listeners.push(Interceptor.attach(m.base.add(va),callbacks));}
  try {
  hook('0xa17f70',{
    onEnter(args){
      this.tid=Process.getCurrentThreadId();this.tracked=false;
      try{
        const operation=cppString(args[2]);if(operation!=='mobileconfig_qe_info')return;
        const c={id:++sequence,operation,method:cppString(args[1]),chunks:[],bytes:0,created_ms:Date.now()};
        const list=active.get(this.tid)||[];list.push(c);active.set(this.tid,list);this.tracked=true;
        const begin=args[3].readPointer(),end=args[3].add(8).readPointer();
        const count=parseInt(end.sub(begin).toString(),16)/48;
        if(!Number.isInteger(count)||count<0||count>512)throw Error('request_vector_size');
        const fields={};
        for(let i=0;i<count;i++){
          const pair=begin.add(i*48),key=cppString(pair);
          if(key==='device_id'){const n=cppSize(pair.add(24));fields.device_id={present:Boolean(n),length:n};continue;}
          if(!['needs_name','skip_qe','with_universe_params','with_current_experiment_group','with_only_current_experiment_group','with_experiments','with_params','with_groups','with_group_params','with_gatekeepers','api_version','queries'].includes(key))continue;
          const value=cppString(pair.add(24));
          if(['needs_name','skip_qe','with_universe_params','with_current_experiment_group','with_only_current_experiment_group','with_experiments','with_params','with_groups','with_group_params','with_gatekeepers','api_version'].includes(key))fields[key]=/^\d{1,5}$/.test(value)?value:'non_numeric';
          else if(key==='queries'){try{const q=JSON.parse(value);fields.queries={is_array:Array.isArray(q),count:Array.isArray(q)?q.length:null};}catch(_){fields.queries={json:false};}}
        }
        emit('qe_request_contract',{request_id:c.id,method:c.method,operation,parameter_count:count,fields});
      }catch(e){emit('observer_error',{stage:'request',message:String(e)});}
    },
    onLeave(){if(this.tracked){const stack=active.get(this.tid)||[];stack.pop();if(!stack.length)active.delete(this.tid);}}
  });
  hook('0xa15ab4',{onEnter(args){
    const stack=active.get(Process.getCurrentThreadId())||[],c=stack[stack.length-1];if(!c)return;
    if(objects.size>=64){emit('observer_capacity',{limit:64});return;}
    objects.set(args[0].toString(),c);emit('qe_callback_correlated',{request_id:c.id});
  }});
  hook('0xfde218',{onEnter(args){const c=objects.get(args[0].toString());if(c){try{c.statusCandidate=args[1].readU16();emit('qe_response_observed',{request_id:c.id,http_status_candidate:c.statusCandidate,status_source:'TigonResponse_first_u16_static_layout'});}catch(e){emit('observer_error',{request_id:c.id,stage:'response',message:String(e)});}}}});
  hook('0xfde24c',{onEnter(args){const c=objects.get(args[0].toString());if(!c)return;
    if(c.bodyError)return;
    try{const b=copyChain(args[1].readPointer());if(c.bytes+b.length>2097152)throw Error('body_limit');c.chunks.push(b);c.bytes+=b.length;}
    catch(e){c.bodyError=String(e);c.chunks=[];c.bytes=0;}
  }});
  function finish(args,terminal){
    const key=args[0].toString(),c=objects.get(key);if(!c)return;objects.delete(key);
    const bytes=new Uint8Array(c.bytes);let off=0;for(const b of c.chunks){bytes.set(b,off);off+=b.length;}
    emit('qe_transport_diagnostic',{request_id:c.id,terminal,http_status_candidate:c.statusCandidate??null,capture_error:c.bodyError??null,native_error:c.nativeError??null,...responseInfo(bytes)});
  }
  hook('0xfde27c',{onEnter(args){finish(args,'onEOM');}});
  hook('0x3fdda18',{onEnter(args){const c=objects.get(args[0].toString());if(c){try{c.nativeError={domain:redact(cppString(args[1].add(8))),code:args[1].add(32).readS64().toString(),detail:redact(cppString(args[1].add(40)))};}catch(e){c.nativeError={read_error:String(e)};}}finish(args,'onError');}});
  emit('observer_ready',{build:'583.0.0/1090364060',uuid,device_execution:'authorized_test_process_only'});
  } catch(e) {
    for(const listener of listeners)listener.detach();
    throw e;
  }
}
if(typeof module!=='undefined'&&module.exports)module.exports={redact,responseInfo,copyChain};
else {try{startObserver();}catch(e){send({event:'observer_start_failed',message:String(e)});}}
