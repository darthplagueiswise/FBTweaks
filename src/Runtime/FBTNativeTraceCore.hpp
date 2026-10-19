#ifndef FBT_NATIVE_TRACE_CORE_HPP
#define FBT_NATIVE_TRACE_CORE_HPP
// Bounded, optional trace store: no allocation or disk access on writes.
#include <atomic>
#include <array>
#include <cstdint>
#include <ctime>
#include <mutex>
#include <vector>
namespace fbt_trace {
static const size_t CAPACITY=256, NAME_MAX=112, NOTE_MAX=176;
enum Kind { BOOL_CALL=1, NETWORK=2, SYSTEM=3 };
struct Record {
 uint64_t sequence,monotonic_ns;
 int kind,original,effective;
 char name[NAME_MAX],note[NOTE_MAX];
};
class Ring {
public:
 Ring():active_(false),next_(0),count_(0),dropped_(0),serial_(0){}
 void setEnabled(bool b){active_.store(b,std::memory_order_release);}
 bool enabled()const{return active_.load(std::memory_order_acquire);}
 bool add(int kind,const char*name,const char*note,int original,int effective){
  if(!enabled())return false;
  if(!mutex_.try_lock()){dropped_.fetch_add(1,std::memory_order_relaxed);return false;}
  Record&r=records_[next_]; r.sequence=++serial_;
  timespec t={};clock_gettime(CLOCK_MONOTONIC,&t);
  r.monotonic_ns=uint64_t(t.tv_sec)*1000000000ULL+uint64_t(t.tv_nsec);
  r.kind=kind;r.original=original;r.effective=effective;
  copy(r.name,name);copy(r.note,note);
  next_=(next_+1)%CAPACITY;if(count_<CAPACITY)++count_;
  mutex_.unlock();return true;
 }
 std::vector<Record>snapshot(){
  std::lock_guard<std::mutex>guard(mutex_);
  std::vector<Record>out;out.reserve(count_);
  size_t first=(next_+CAPACITY-count_)%CAPACITY;
  for(size_t i=0;i<count_;++i)out.push_back(records_[(first+i)%CAPACITY]);
  return out;
 }
 void clear(){std::lock_guard<std::mutex>guard(mutex_);count_=0;next_=0;dropped_.store(0,std::memory_order_relaxed);}
 uint64_t dropped()const{return dropped_.load(std::memory_order_relaxed);}
private:
 template<size_t N>static void copy(char(&dst)[N],const char*src){
  if(!src){dst[0]='\0';return;}
  size_t i=0;for(;i+1<N&&src[i];++i)dst[i]=src[i];dst[i]='\0';
 }
 std::atomic<bool>active_;std::mutex mutex_;
 std::array<Record,CAPACITY>records_;
 size_t next_,count_;std::atomic<uint64_t>dropped_;uint64_t serial_;
};
}
#endif
