'use strict';
const assert=require('assert');const {redact,responseInfo,copyChain}=require('./trace_names_transport.js');let checks=0;
function test(name,fn){fn();checks++;console.log('PASS '+name);}
const enc=s=>new Uint8Array(Buffer.from(s));
test('native description is never server JSON',()=>assert.equal(responseInfo(enc('None domain: FBHTTPErrorDomain code: 400 detail: ')).body_status,'native_error_summary_NOT_server_JSON'));
test('server error code and sanitized message survive',()=>{const r=responseInfo(enc(JSON.stringify({error:{code:100,error_subcode:33,message:'bad queries for 1479635203',access_token:'secret'}})));assert.equal(r.error.code,100);assert(!JSON.stringify(r).includes('1479635203'));assert(!JSON.stringify(r).includes('secret'));});
test('names are counted without exposing names or values',()=>{const r=responseInfo(enc('{"id_to_names":["1:test:0:flag"]}'));assert.equal(r.name_record_count,1);assert(!JSON.stringify(r).includes('flag'));});
test('no bytes means unavailable, never captured empty JSON',()=>assert.equal(responseInfo(enc('')).body_status,'not_delivered_to_observed_callback'));
test('gzip is labeled without interpreting compressed bytes',()=>assert.equal(responseInfo(new Uint8Array([31,139,1])).body_status,'gzip_not_decoded'));
test('credentials and URLs are removed',()=>{const s=redact('access_token=EAA1234567890123456789 https://x.test/?token=foo a@b.com');assert(!s.includes('foo'));assert(!s.includes('EAA'));assert(!s.includes('a@b.com'));});
test('quoted credentials are removed',()=>{const s=redact('{"access_token":"sensitive-value","message":"invalid field"}');assert(!s.includes('sensitive-value'));assert(s.includes('invalid field'));});
test('authorization bearer is fully removed',()=>{const s=redact('Authorization: Bearer abc.def.ghi');assert(!s.includes('abc.def.ghi'));});
test('standalone bearer is removed',()=>assert(!redact('failed Bearer abc.def.ghi').includes('abc.def.ghi')));
test('messages stay bounded',()=>assert(redact('x'.repeat(4096)).length<=1024));
class P {
 constructor(id,offset=0){this.id=id;this.offset=offset;}
 add(n){return new P(this.id,this.offset+n);}isNull(){return this.id===null;}equals(q){return this.id===q.id&&this.offset===q.offset;}toString(){return this.id+':'+this.offset;}
 readU64(){return BigInt(nodes[this.id].length);}readPointer(){const n=nodes[this.id];return this.offset===8?new P(n.data):new P(n.next);}
 readByteArray(n){return Uint8Array.from(data[this.id].slice(0,n)).buffer;}
}
let nodes={},data={};
test('multiple IOBuf segments copy in order',()=>{nodes={a:{length:2,data:'d1',next:'b'},b:{length:1,data:'d2',next:'a'}};data={d1:[65,66],d2:[67]};assert.deepEqual(Array.from(copyChain(new P('a'))),[65,66,67]);});
test('broken chain is rejected',()=>{nodes={a:{length:0,data:null,next:null}};assert.throws(()=>copyChain(new P('a')),/broken_chain/);});
test('non-head cycles are rejected',()=>{nodes={a:{length:0,data:null,next:'b'},b:{length:0,data:null,next:'b'}};assert.throws(()=>copyChain(new P('a')),/cycle/);});
test('oversized bodies are rejected before read',()=>{nodes={a:{length:2097153,data:null,next:'a'}};assert.throws(()=>copyChain(new P('a')),/body_limit/);});
test('positive length with null data is rejected',()=>{nodes={a:{length:1,data:null,next:'a'}};assert.throws(()=>copyChain(new P('a')),/null_data/);});
console.log(JSON.stringify({host_fixture_checks:checks,iphone_execution:false}));
