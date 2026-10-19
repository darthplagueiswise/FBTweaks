#include "../src/Runtime/FBTNativeTraceCore.hpp"
#include <cassert>
#include <cstring>
#include <string>
#include <thread>
#include <vector>
#include <iostream>
using fbt_trace::Ring;
int main(){
 Ring ring;
 assert(!ring.enabled());
 assert(!ring.add(1,"FBU#isEmployee","",-1,1));
 assert(ring.snapshot().empty());
 ring.setEnabled(true);
 assert(ring.add(1,"FBUserPreferences#isEmployee","",0,1));
 auto snap=ring.snapshot();
 assert(snap.size()==1);
 assert(snap[0].kind==1&&snap[0].original==0&&snap[0].effective==1);
 assert(std::strcmp(snap[0].name,"FBUserPreferences#isEmployee")==0);
 std::string longText(1000,'X');
 ring.add(2,longText.c_str(),longText.c_str(),-1,-1);
 snap=ring.snapshot();
 assert(std::strlen(snap.back().name)==fbt_trace::kNameBytes-1);
 assert(std::strlen(snap.back().note)==fbt_trace::kNoteBytes-1);
 for(int i=0;i<310;++i)ring.add(2,"qe_info_response","http_status=400",-1,-1);
 snap=ring.snapshot();
 assert(snap.size()==fbt_trace::CAPACITY);
 assert(snap.front().sequence<snap.back().sequence);
 assert(snap.front().sequence==snap.back().sequence-(fbt_trace::CAPACITY-1));
 ring.setEnabled(false);
 assert(!ring.add(1,"nothing","",0,1));
 assert(ring.snapshot().size()==fbt_trace::CAPACITY);
 ring.clear();assert(ring.snapshot().empty());
 ring.setEnabled(true);
 std::vector<std::thread>threads;
 for(int i=0;i<4;++i)threads.emplace_back([&ring]{
  for(int n=0;n<500;n++)ring.add(1,"SomeClass#boolMethod","",-1,1);
 });
 for(auto&t:threads)t.join();
 snap=ring.snapshot();
 assert(snap.size()<=fbt_trace::CAPACITY);
 for(size_t i=1;i<snap.size();i++)assert(snap[i].sequence>snap[i-1].sequence);
 std::cout<<"PASS NativeTraceCoreTests"<<std::endl;
}
