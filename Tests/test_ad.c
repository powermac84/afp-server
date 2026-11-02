#include "../Source/AD.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static void w16(unsigned char*p,unsigned n){p[0]=n>>8;p[1]=n;}
static void w32(unsigned char*p,uint32_t n){p[0]=n>>24;p[1]=n>>16;p[2]=n>>8;p[3]=n;}
static void base(unsigned char*b){memset(b,0,128);w32(b,0x00051607);w32(b+4,0x00020000);w16(b+24,2);w32(b+26,9);w32(b+30,50);w32(b+34,32);w32(b+38,2);w32(b+42,82);w32(b+46,8);memcpy(b+50,"TEXTttxt",8);memcpy(b+82,"FORKDATA",8);}
int main(void){unsigned char b[128];int checks=0;
#define T(x) do{assert(x);checks++;}while(0)
 T(!ad_parts(NULL,0).valid);base(b);ADParts a=ad_parts(b,128);T(a.valid&&a.finderOffset==50&&a.finderLength==32&&a.resourceOffset==82&&a.resourceLength==8);T(a.count==2);
 T(!ad_parts(b,25).valid);T(!ad_parts(b,49).valid);T(!ad_parts(b,89).valid);
 b[0]=1;T(!ad_parts(b,128).valid);base(b);w32(b+4,3);T(!ad_parts(b,128).valid);base(b);w32(b+4,0x10000);T(ad_parts(b,128).valid);
 base(b);w16(b+24,65535);T(!ad_parts(b,128).valid);base(b);w32(b+30,49);T(!ad_parts(b,128).valid);base(b);w32(b+34,31);T(!ad_parts(b,128).valid);
 base(b);w32(b+42,60);T(!ad_parts(b,128).valid);base(b);w32(b+38,9);w32(b+46,32);T(!ad_parts(b,128).valid);base(b);w32(b+42,0xfffffff0);w32(b+46,0x40);T(!ad_parts(b,128).valid);
 base(b);w32(b+46,0);T(ad_parts(b,128).valid);memset(b,0,128);T(ad_all_zero(b,128));b[127]=1;T(!ad_all_zero(b,128));T(ad_all_zero(NULL,0));T(!ad_all_zero(NULL,1));
 T(ad_path_contains("/share","/share"));T(ad_path_contains("/share","/share/file"));T(!ad_path_contains("/share","/share-two"));T(!ad_path_contains("/share/sub","/share"));T(ad_path_contains("/","/share"));T(!ad_path_contains(NULL,"/share"));T(!ad_path_contains("share","/share"));T(!ad_path_contains("/share",NULL));
 T(!ad_path_contains("/share","/share/../private"));T(!ad_path_contains("/share","/share/./file"));T(!ad_path_contains("/share","/share//file"));
 T(ad_path_contains("/share/","/share/file"));T(ad_path_contains("/share/","/share/"));T(ad_path_contains("/share","/share/.hidden"));T(!ad_path_contains("/share/../private","/share/../private/file"));
 base(b);w32(b+38,2);w32(b+26,2);w32(b+34,0);T(!ad_parts(b,128).valid);
 unsigned seed=0x12345678;for(int j=0;j<100000;j++){for(size_t k=0;k<sizeof b;k++){seed=seed*1664525u+1013904223u;b[k]=(unsigned char)(seed>>24);}if(j%3==0){w32(b,0x00051607);w32(b+4,0x20000);w16(b+24,j%9);}a=ad_parts(b,(size_t)(j%129));if(a.valid){T(a.finderOffset+a.finderLength<=128);T(a.resourceOffset+a.resourceLength<=128);}}
 printf("PASS: %d assertions; 100000 fuzz inputs.\n",checks);return 0;}
