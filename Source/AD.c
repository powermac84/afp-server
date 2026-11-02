#include "AD.h"
static uint16_t be16(const unsigned char *p){return (uint16_t)(((uint16_t)p[0]<<8)|p[1]);}
static uint32_t be32(const unsigned char *p){return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];}
ADParts ad_parts(const unsigned char *p,size_t n){
    ADParts a={0};
    if(!p || n<26 || be32(p)!=0x00051607u) return a;
    uint32_t v=be32(p+4); if(v!=0x00020000u && v!=0x00010000u) return a;
    unsigned count=be16(p+24); if(count>4096 || 26u+(size_t)count*12u>n)return a;
    size_t head=26u+(size_t)count*12u;
    for(unsigned i=0;i<count;i++){
        const unsigned char *e=p+26+12*i;
        uint32_t id=be32(e),off=be32(e+4),len=be32(e+8);
        if((size_t)off>n || (size_t)len>n-(size_t)off || (len && off<head))return (ADParts){0};
        if(id==9){if(a.finderLength || len<32)return (ADParts){0};a.finderOffset=off;a.finderLength=len;}
        if(id==2){if(a.resourceLength)return (ADParts){0};a.resourceOffset=off;a.resourceLength=len;}
        for(unsigned j=0;j<i;j++){
            const unsigned char *q=p+26+12*j;uint32_t qo=be32(q+4),ql=be32(q+8);
            if(len && ql && (uint64_t)off+len>qo && (uint64_t)qo+ql>off)return (ADParts){0};
            if((id==9||id==2)&&be32(q)==id)return (ADParts){0};
        }
    }
    a.count=(uint16_t)count;a.valid=1;return a;
}
int ad_all_zero(const unsigned char *p,size_t n){if(!p&&n)return 0;for(size_t i=0;i<n;i++)if(p[i])return 0;return 1;}
/* Callers resolve symlinks separately. Reject lexical traversal here as a
 * second boundary check, instead of accepting "/share/../private" by prefix. */
static int absolute_clean_path(const char *p){
    if(!p||p[0]!='/')return 0;
    const char *s=p+1;
    while(*s){
        const char *start=s;while(*s&&*s!='/')s++;
        size_t length=(size_t)(s-start);
        if(!length||(length==1&&start[0]=='.')||(length==2&&start[0]=='.'&&start[1]=='.'))return 0;
        if(*s)s++;
    }
    return 1;
}
int ad_path_contains(const char *root,const char *child){
    if(!absolute_clean_path(root)||!absolute_clean_path(child))return 0;
    size_t length=0;while(root[length])length++;
    while(length>1&&root[length-1]=='/')length--;
    size_t i=0;while(i<length&&child[i]&&root[i]==child[i])i++;
    if(i!=length)return 0;
    return !child[i]||length==1||child[i]=='/';
}
