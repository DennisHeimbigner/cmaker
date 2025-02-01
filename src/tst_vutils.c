/*********************************************************************
 *   Copyright 2018, UCAR/Unidata
 *   See netcdf/COPYRIGHT file for copying and redistribution conditions.
 *********************************************************************/

/**
Test the vutils code
*/

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

#include "vutils.h"

/* Provide a big buffer for use of snprintf */
static char pbuf[8192];
/* And one for numbers */
static char digits[64];
/* And a vs buffer */
static VString* vsbuf = NULL;

/**************************************************/
/* Support utility functions */

static const char*
printvlist(VList* vl)
{
    size_t i;
    vssetlength(vsbuf,0);        
    snprintf(pbuf,sizeof(pbuf),"vlist[%zu](",vlistlength(vl));
    for(i=0;i<vlistlength(vl);i++) {
	uintptr_t elem = (uintptr_t)vlistget(vl,i);
	snprintf(digits,sizeof(digits),"%s%llu",(i==0?"":","),(unsigned long long)elem);
	vscat(vsbuf,digits);
    }
    strcat(pbuf,vscontents(vsbuf));
    strcat(pbuf,")");
    return pbuf;
}

/**************************************************/

void
testvlist(void)
{
#define NTVL 4
    size_t i;
    uintptr_t uip;
    VList* vl = vlistnew();
    VList* clone = NULL;

    /* Fill up the list using various functions */
    for(i=0;i<NTVL;i++) vlistpush(vl,(void*)(uintptr_t)i);
    vlistinsert(vl,4,(void*)(uintptr_t)31);
    vlistinsert(vl,0,(void*)(uintptr_t)17);
    vlistinsert(vl,3,(void*)(uintptr_t)19);
    printvlist(vl);

    /* Set a couple of values */
    vlistset(vl,5,(void*)(uintptr_t)91);
    vlistset(vl,3,(void*)(uintptr_t)92);
    vlistset(vl,0,(void*)(uintptr_t)93);
    printvlist(vl);

    /* Remove a couple of values */
    uip = (uintptr_t)vlistremove(vl,0);
    snprintf(pbuf,sizeof(pbuf),"remove [%u] = %u\n",(unsigned)0,(unsigned)uip);
    i = (size_t)vlistlength(vl)-1;
    uip = (uintptr_t)vlistremove(vl,i);
    snprintf(pbuf,sizeof(pbuf),"remove [%u] = %u\n",(unsigned)i,(unsigned)uip);
    uip = (uintptr_t)vlistremove(vl,4);
    snprintf(pbuf,sizeof(pbuf),"remove [%u] = %u\n",(unsigned)4,(unsigned)uip);
    printvlist(vl);

    /* Clone the list */
    clone = vlistclone(vl);    
    printvlist(clone);

    /* Change the list length */
    vlistsetlength(vl,(unsigned)vlistlength(vl)/2);
    printvlist(vl);

    /* Clear the list */
    vlistclear(vl);
    printvlist(vl);
    
    vlistfree(vl);
}

int
main(int argc, char** argv)
{
    vsbuf = vsnew();
    testvlist();
    return 0;
}
