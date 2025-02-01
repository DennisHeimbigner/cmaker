/* Copyright 2025, Dennis Heimbigner
   See the COPYRIGHT.md file for more information. */

#ifndef VUTILS_H
#define VUTILS_H 1

/* Define a header-only simple version of a dynamically expandable list and byte buffer */
/* To be used in code that should be independent of libnetcdf */

typedef struct VList {
    size_t alloc;
    size_t length;
    void** content;
} VList;

typedef struct VString {
    int nonextendible; /* 1 = > fail if an attempt is made to extend this string*/
    size_t alloc;
    size_t length;
    char* content;
} VString;

/* Insertion sort + binary search.
   This provides a simple alternative
   to a full-blown hashtable while providing
   a reasonable efficiency for small to medium
   sets of objects.
*/

/* We assume the use of a comparison function*/

typedef int Vsortcmp(const void* key, const void** elemp); /* for search */
typedef const void* Vsortkey(const void* elem); /* extract pointer to key */

typedef struct VSort {
    VList* table;
    Vsortcmp* compare;
    Vsortkey* getkey;
} VSort;

/* VString has a fixed expansion size */
#define VSTRALLOC 64

#if defined(_CPLUSPLUS_) || defined(__CPLUSPLUS__)
#define EXTERNC extern "C"
#else
#define EXTERNC extern
#endif

/* Begin vlist API */
static VList* vlistnew(void);
static void vlistfree(VList* l);
static void* vlistget(VList* l, size_t index) /* Return the ith element of l */;
static void* vlistset(VList* l, size_t index, void* elem);
static void* vlistinsert(VList* l, size_t index, void* elem);
static void* vlistremove(VList* l, size_t index) /* remove index'th element */;
static VList* vlistclone(VList* l);
static void vlistfreeall(VList* l) /* call free() on each list element*/;

/* Following are always "in-lined"*/
#define vlistcontents(l)  ((l) == NULL?NULL:(l)->content)
#define vlistlength(l)  ((l) == NULL?0:(l)->length)
#define vlistpush(l,elem) vlistinsert(l,vlistlength(l),elem)
#define vlistpop(l) vlistremove(l,vlistlength(l)-1)
#define vlistqpop(l) vlistremove(l,0)
#define vlistsetlength(l,len)  do{if((l)!= NULL) (l)->length = len;} while(0)
#define vlistclear(l)  vlistsetlength(l,0)
/* End vlist API */

static VList*
vlistnew(void)
{
    VList* l;
    l = (VList*)calloc(1,sizeof(VList));
    assert(l != NULL);
    return l;
}

static void
vlistfree(VList* l)
{
    if(l == NULL) return;
    if(l->content != NULL) {free(l->content); l->content = NULL;}
    free(l);
}

/** Expand the contents of the list
Guarantees that l->content != NULL.
@param l
@param minalloc allocation space needed
@return void
*/
static void
vlistexpand(VList* l, size_t minalloc)
{
    void** newcontent = NULL;
    size_t newsize;

    assert(l != NULL);
    if(minalloc == 0) minalloc++; /* guarantee allocated space */
    newsize = l->alloc;
    while(newsize < minalloc)
      newsize = (newsize * 2) + 1; /* basically double allocated space */
    if(l->alloc >= newsize) return; /* space already allocated */
    newcontent = (void**)calloc(newsize,sizeof(void*));
    assert(newcontent != NULL);
    if(l->alloc > 0 && l->length > 0 && l->content != NULL) { /* something to copy */
	memcpy((void*)newcontent,(void*)l->content,sizeof(void*)*l->length);
    }
    if(l->content != NULL) free(l->content);
    l->content = newcontent;
    l->alloc = newsize;
    /* length is the same */  
}

static void*
vlistget(VList* l, size_t index) /* Return the ith element of l */
{
    if(l == NULL || l->length == 0) return NULL;
    assert(index < l->length);
    return l->content[index];
}

/* Overwrite element at position index.
@param l list
@param index where to insert
@param elem what to insert
@return NULL or previous value if overwriting
*/
static void*
vlistset(VList* l, size_t index, void* elem)
{
    void* old = NULL;
    assert(l != NULL);
    vlistexpand(l,l->alloc); /* Make sure there is a content object */
    if(index > l->length)
	memset(&l->content[l->length],0,index - l->length);
    old = l->content[index];
    l->content[index] = elem;
    l->length++;
    return old;
}

/* insert (not overwrite) element at position index.
@param l list
@param index where to insert
@param elem what to insert
@return elem to allow chains
*/
static void*
vlistinsert(VList* l, size_t index, void* elem)
{
    assert(l != NULL);
    vlistexpand(l,index+1); /* Make sure there is a content object */
    if(index > l->length)
	memset(&l->content[l->length],0,index - l->length);
    if(l->length > 0) {
	size_t i;
        for(i=l->length;i>=index;i--) l->content[i+1] = l->content[i];
    }
    l->content[index] = elem;
    l->length++;
    return elem;
}

static void*
vlistremove(VList* l, size_t index) /* remove index'th element */
{
    size_t i,len;
    void* elem = NULL;
    if(l == NULL || l->length == 0) goto done;
    elem = l->content[index];
    for(i=index+1;i<l->length;i++) l->content[i-1] = l->content[i];
    l->length--;
done:
    return elem;  
}

/* Do a shallow clone of a list */
static VList*
vlistclone(VList* l)
{
    size_t i;
    VList* clone = vlistnew();
    vlistexpand(clone,l->length);
    for(i=0;i < l->length;i++) {
        vlistpush(clone,vlistget(l,i));
    }
    return clone;
}

static void
vlistfreeall(VList* l) /* call free() on each list element*/
{
    size_t i;
    if(l == NULL || l->length == 0) return;
    for(i = 0;i<l->length;i++) if(l->content[i] != NULL) {free(l->content[i]);}
    vlistfree(l);
}

/**************************************************/

/* Begin vstring API */
static VString* vsnew(void);
static void vsfree(VString* vs);
static void vscat(VString* vs, const char* elem);
static void vsappendn(VString* vs, const char* elem, unsigned n);
static void vsappend(VString* vs, int elem);
static void vssetcontents(VString* vs, char* contents, unsigned alloc);
static char* vsextract(VString* vs);

/* Following are always "in-lined"*/
#define vscontents(vs)  ((vs) == NULL?NULL:(vs)->content)
#define vslength(vs)  ((vs) == NULL?0:(vs)->length)
#define vscat(vs,s)  vsappendn(vs,s,0)
#define vsclear(vs)  vssetlength(vs,0)
#define vssetlength(vs,len)  do{if((vs)!= NULL) (vs)->length = len;} while(0)
/* End vstring API */

static VString*
vsnew(void)
{
    VString* vs = NULL;
    vs = (VString*)calloc(1,sizeof(VString));
    assert(vs != NULL);
    return vs;
}

static void
vsfree(VString* vs)
{
    if(vs == NULL) return;
    if(vs->content != NULL) free(vs->content);
    free(vs);
}

static void
vsexpand(VString* vs, size_t minalloc)
{
    char* newcontent = NULL;
    size_t newsize;

    if(vs == NULL) return;
    assert(vs->nonextendible == 0);
    newsize = vs->alloc;
    while(newsize < minalloc)
      newsize = (newsize * 2) + 1; /* basically double allocated space */
    if(vs->alloc >= newsize) return; /* space already allocated */
    newcontent = (char*)calloc(1,newsize+1);/* always room for nul term */
    assert(newcontent != NULL);
    if(vs->alloc > 0 && vs->length > 0 && vs->content != NULL) /* something to copy */
    memcpy((void*)newcontent,(void*)vs->content,vs->length);
    newcontent[vs->length] = '\0'; /* ensure null terminated */
    if(vs->content != NULL) free(vs->content);
    vs->content = newcontent;
    vs->alloc = newsize;
    /* length is the same */  
}

static void
vsappendn(VString* vs, const char* elem, unsigned n)
{
    size_t need;
    assert(vs != NULL && elem != NULL);
    if(n == 0) {n = (unsigned)strlen(elem);}
    need = vs->length + n;
    if(vs->nonextendible) {
     /* Space must already be available */
      assert(vs->alloc >= need);
    } else {
      vsexpand(vs,need);
    }
    memcpy(&vs->content[vs->length],elem,n);
    vs->length += n;
    if(!vs->nonextendible)
      vs->content[vs->length] = '\0'; /* guarantee nul term */
}

static void
vsappend(VString* vs, int elem)
{
    char s[2];
    s[0] = (char)elem;
    s[1] = '\0';
    vsappendn(vs,s,1);
}

/* Set unexpandible contents */
static void
vssetcontents(VString* vs, char* contents, unsigned alloc)
{
    assert(vs != NULL && contents != NULL);
    vs->length = 0;
    if(!vs->nonextendible && vs->content != NULL) free(vs->content);
    vs->content = contents;
    vs->length = alloc;
    vs->alloc = alloc;
    vs->nonextendible = 1;
}

/* Extract the content and leave content null */
static char*
vsextract(VString* vs)
{
    char* x = NULL;
    if(vs == NULL) return NULL;
    if(vs->content == NULL) {
        /* guarantee content existence and nul terminated */
        if((vs->content = calloc(1,sizeof(char))) == NULL) return NULL;
        vs->length = 0;
    }
    x = vs->content;
    vs->content = NULL;
    vs->length = 0;
    vs->alloc = 0;
    return x;
}

/**************************************************/

/* Provide a table of values that can be searched with
   reasonable efficiency.  For simplicity, we choose to keep a
   sorted table and use binary search. A hash table would be
   faster, but this assumes the table is not "big".
*/

/* Begin vsort API */
static VSort* vsortnew(Vsortcmp cmpfcn, Vsortkey getkey);
static void vsortfree(VSort* sl);
static VSort* vsortclone(VSort* sl);
static int vsortsorter(const void** elemp1, const void** elemp2, void* arg);
static void vsortsort(VSort* sl);
static int vsortindex(VSort* sl, const void* key, size_t* indexp);
static void* vsortinsert(VSort* sl, void* elem);
static void* vsortsearch(VSort* sl, const void* key);
/* End vsort API */

/**
@param cmpfcn to compare key against element
@param getkey return a pointer to the key of an element
@return created VSort object
static VSort*
vsortnew(Vsortcmp cmpfcn, Vsortkey getkey)
{
    VSort* sl;
    sl = (VSort*)calloc(1,sizeof(VSort));
    assert(sl != NULL);
    sl->table = vlistnew();  
    sl->compare = cmpfcn;
    sl->sorter = sortfcn;
    return sl;
}

static void
vsortfree(VSort* sl)
{
    if(sl == NULL) return;
    vlistfree(sl->table);
    free(sl);
}

/* Shallow clone */
static VSort*
vsortclone(VSort* sl)
{
    VSort* clone = NULL;
    if(sl == NULL) goto done;
    clone = (VSort*)calloc(1,sizeof(VSort));
    if(clone == NULL) goto done;
    clone->compare = sl->compare;
    clone->getkey = sl->getkey;
    clone->table = vlistclone(sl->table); /* shallow */
done:
    return clone;
}
/* Use getkey+compare to implement a sort comparison function */
static int
vsortsorter(const void** elemp1, const void** elemp2, void* arg)
{
    VSort* sl = (VSort*)arg;
    const void* key = sl->getkey(*elemp1);
    return sl->compare(key,elemp2);
}

/**
Sort the contents of an existing VSort.
@param sl VSort to sort
@param cmp sorting comparison function
@return void
*/
static void
vsortsort(VSort* sl)
{
    assert(sl != NULL);
    if(vlistlength(sl->table) == 0) return;
    qsort_r(vlistcontents(sl->table), vlistlength(sl->table), sizeof(void*), vsortsorter,(void*)sl);
}


/**
Locate the index of an element in the list of elements.
@param key of the element to find (deliberately use uintptr_t to allow both ptr and int).
@param indexp contain location or insertion point of the element
@return 1 if found; 0 if not found
*/
static int
vsortindex(VSort* sl, const void* key, size_t* indexp)
{
    int found = 0;
    size_t L,R,n;
    const void** table = NULL;

    assert(sl != NULL);
    n = vlistlength(sl->table);
    if(n == 0) {found = 0; L = 0; goto done;} /* insert at position 0 */
    table = (const void**)vlistcontents(sl->table);
    L = 0; R = n;
    while(L < R) {
	int diff;
        size_t m = (size_t)((L+R)/2); /* integer floor */
	diff = sl->compare(key,&table[m]); /* pointer to elem */
	if(diff == 0) found = 1;
        if(diff > 0) {L = (m+1);} else {R = m;}
    }
    if(!found) L++; /* insertion index point */
done:
    if(indexp) *indexp = L;
    return found;
}

/**
Do a sorted insertion.
@param sl VSort into which the new element is inserted
@param el new element to insert
@return previous element if overwritten, NULL otherwise
*/
static void*
vsortinsert(VSort* sl, void* elem)
{
    void* prev = NULL;
    const void* key = NULL;
    size_t insertpoint;

    assert(sl != NULL);
    key = sl->getkey(elem);
    if(!vsortindex(sl,key,&insertpoint)) {
	/* Element is not in the table currently */
	vlistinsert(sl->table,insertpoint,elem);
    } else {/* There is a previous element */
        prev = vlistget(sl->table,insertpoint);	
        vlistset(sl->table,insertpoint,elem);
    }
    return prev;
}

/**
Search for a key in the table
@param sl VSort to search
@param key for which to search
@return matching element, NULL if not found
*/
static void*
vsortsearch(VSort* sl, const void* key)
{
    void* match = NULL;
    size_t insertpoint;

    if(vsortindex(sl,key,&insertpoint))
        match = vlistget(sl->table,insertpoint); /* Matching element exists */
    return match;
}

#endif /*NCVUTIL_H*/
