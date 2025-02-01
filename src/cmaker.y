/*********************************************************************
 *   Copyright 2025, Dennis Heimbigner
 *   See COPYRIGHT.md file for copying and redistribution conditions.
 *********************************************************************/

/* bison source for the cmaker parser */

%define parse.error detailed
%define api.prefix {cmk}
%define api.pure full
%param {struct GlobalState* globalstate}
%locations

%code top {
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>

#if defined(_WIN32) && !defined(__MINGW32__)
#include "XGetopt.h"
#else
#include <getopt.h>
#endif

#include "vutils.h"

/* parser controls */
#define YY_NO_INPUT 1

#define MAX_NAME 64 /* Including nul termination */
#define nullify(s) ((s)==NULL || (s)[0]=='\0'?NULL:(s))

typedef enum Boolean {False=0, True=1, None=-1} Boolean;
typedef enum Sort {SORT_NONE=0, SORT_OPT=1, SORT_PROP=2, SORT_LIB=3, SORT_CON=4} Sort;
typedef enum TypeType {UNTYPED=0, BOOL_TYPE=1, STRING_TYPE=2, INTEGER_TYPE=3, DOUBLE_TYPE=4} TypeType;
typedef enum ExprSort {
	XSORT_NONE=0,
	XSORT_OR=1,
	XSORT_AND=2,
	XSORT_NONET=3,
	XSORT_SET=4,
	XSORT_TRUE=5,
	XSORT_FALSE=6,
	XSORT_STRING=7,
	XSORT_INTEGER=8,
	XSORT_DOUBLE=9,
	XSORT_ID=10,
	XSORT_PATH=11,
} ExprSort;

typedef struct IdentPair {
    char namespace[MAX_NAME];
    char id[MAX_NAME];
} IdentPair;

/* We use struct rather than Union */
typedef struct Konst {
    ExprSort sort;
    char* id;
    char* sval;
    long long ival;
    double dval;
    /* Note that Boolean is encoded in op */
} Konst;
static const Konst EmptyKonst = {XSORT_NONE,NULL,NULL,0,0.0};

#if 0
typedef struct String {
    size_t length;
    char* str;
} String;
#endif

typedef struct Expr {
    ExprSort sort;
    struct Expr* lr[2]; /* left, then right | Unary==left */
    Konst value; /* when Expr is atomic constant */
} Expr;

typedef struct Object {
    Sort sort;
    char* id;
    char* template;
} Object;

typedef struct Option {
    Object hdr;
    TypeType typ;
    Expr* expr;
} Option;

typedef struct Property {
    Object hdr;
    TypeType typ;
    Expr* expr;
} Property;

typedef struct Library {
    Object hdr;
    char* path;
} Library;


typedef struct Constraint {
    Object hdr;
    Expr* input;
    VList* outputs;    /* VList<Expr*> */
    VList* inputrefs;  /* VList<Expr*> */
    VList* outputrefs; /* VList<Expr*> */
    VList* edges; /* VList<Constraint*> */    
} Constraint;

/* Global State Decls.
   We do this to access certain global state without having to pass it
   to all functions.
   Note that this a single global instance, so the parser part
   is not strictly pure.
*/
typedef struct GlobalState {
    struct State {
	VList* allobjects;
	VList* allconstraints;
    } state;
    struct Parser* parser;
    struct Lexer* lexer;
} GlobalState;;
typedef struct Lexer Lexer;

/* Command line options */
typedef struct CMDoptions {
    int debug;
    char infile[4096];
} CMDoptions;

} /* code top */

%union {
    /* Constants */
    Konst konst;
    char* string;
    /* Enums */
    TypeType typetype;
    /* Structs */
    Expr* atomicconst;
    Constraint* constraint;
    Expr* expr;
    Library* library;
    VList* list;
    Object* object;
    Option* option;
    Property* property;
}

%{
static const Konst TrueConst = {XSORT_TRUE};
static const Konst FalseConst = {XSORT_FALSE};

/* Forward */
static Expr* newoutput(Konst id);
static Expr* outputnot(Expr* res);
static Expr* outputset(Konst id, Expr* b);
static Object* newobject(Sort sort, Konst id);
static Constraint* newconstraint(Expr* input, VList* outputs);
static Expr* newexpr(ExprSort op, Expr* left, Expr* right);
static Expr* newprimary(Konst k);
static Option* newoption(Konst id, TypeType typ, Expr* expr, Konst template);
static Property* newproperty(Konst id, TypeType typ, Expr* expr, Konst template);
static Library* newlibrary(Konst id, Konst path, Konst template);
static VList* maptemplate(VList* list, Konst template);
static Konst newtemplate(Konst k);
static void semerror(const char* msg);
static const char* sortname(Sort sort);
static Konst clonekonst(Konst k);

static void collectrefs(VList* allconstraints);

typedef void (*ApplyFcn)(Expr* expr, void* state);
static void walkexpr(Expr* expr, void* state);

/* Return 0/1 as elem1 matches elem2  */
typedef int (*EqualsFcn)(void* newelem, void* oldelem);
static VList* insertunique(VList* vl, void* newelem, EqualsFcn matcher);
static VList* insertbyptr(VList* vl, void* newelem);
static VList* insertbyname(VList* vl, Object* newelem);

static VList* toposort(struct State* state);
static void compute_edges(VList* allconstraints);
static VList* /*VList<Constraint*>*/ create_edges_for(Constraint* a, VList* allconstraints);
static int intersects(VList* set1, VList* set2);
static void collectrefs(VList* allconstraints);

static void cmkerror(YYLTYPE *locp, struct GlobalState* state, const char* msg);

struct Parser {
    unsigned constraintcounter;
    int debug;
};

struct Lexer {
    int token;
    VString* yytext;
    Konst value;
    YYLTYPE loc;
    int debug;
};

static GlobalState globalstate;
static CMDoptions options;

static int cmklex(YYSTYPE* lvalp, YYLTYPE* llocp, struct GlobalState* state);
%}

%token <konst> ON YES TRUE OFF NO FALSE
%token <konst> BOOL_CONST STRING_CONST INTEGER_CONST DOUBLE_CONST
%token <konst> CONSTANT IDENT PACKAGE_PATH

%token
    /* Token classes */
    /* Keywords */
    AND
    BOOL
    CMAKER
    CONSTRAINTS
    DOUBLE
    END
    IMPLIES
    INTEGER
    LIBRARIES
    LIBRARY
    NOT
    OPTION
    OPTIONS
    OR
    PROPERTIES
    PROPERTY
    STRING

/*
%untyped closer
%untyped cmaker
%untyped header
*/

%type <expr> output
%type <expr> primary
%type <constraint> constraint
%type <list> constraints
%type <list> constraint_list
%type <expr> expr
%type <expr> input
%type <list> libraries
%type <library> library
%type <list> library_list
%type <option> option
%type <list> options
%type <list> option_list
%type <konst> opt_template
%type <list> outputs
%type <list> properties
%type <property> property
%type <list> property_list
%type <typetype> type
%type <expr> value
%type <konst> ident path template constant boolean_constant

%left OR
%left AND
%right NOT

%start cmaker

%%

cmaker:
	header
	options
	properties
	libraries
	constraints
	closer
	;

header:
	CMAKER
	;
closer:
	END CMAKER
	;

template:
	'[' STRING_CONST ']' {$$ = $2;}
	;

opt_template:
	  /*empty*/ {$$ = EmptyKonst;}
	| template {$$ = $1;}
	;

options:
	OPTIONS ':' option_list opt_template {$$ = maptemplate($3,$4);}
	;

option_list:
	  /*empty*/ {$$ = vlistnew();}
	| option_list option {$$ = vlistpush($1,$2);}
	;

option:
	type ident '=' value opt_template ';' {$$ = newoption($2,$1,$4,$5);}
	;

type:
	  /*empty*/ {$$ = UNTYPED;}
	| BOOL {$$ = BOOL_TYPE;}
	| STRING {$$ = STRING_TYPE;}
	| INTEGER {$$ = INTEGER_TYPE;}
	| DOUBLE {$$ = DOUBLE_TYPE;}
	;

properties:
	PROPERTIES ':' property_list opt_template {$$ = maptemplate($3,$4);}
	;

property_list:
	  /*empty*/ {$$ = vlistnew();}
	| property_list property {$$ = vlistpush($1,$2);}
	;

property:
	type ident '=' value opt_template ';' {$$ = newproperty($2,$1,$4,$5);}
	;

value:
	expr {$$=$1;}

libraries:
	LIBRARIES ':' library_list opt_template {$$ = maptemplate($3,$4);}
	;

library_list:
	  /*empty*/ {$$ = vlistnew();}
	| library_list library {$$ = vlistpush($1,$2);}
	;

library:
	ident '=' path opt_template ';' {$$ = newlibrary($1,$3,$4);}
	;

constraints:
	CONSTRAINTS ':' constraint_list opt_template
		{$$ = maptemplate($3,$4);}
	;

constraint_list:
	  /*empty*/ {$$ = vlistnew();}
	| constraint_list constraint {$$ = vlistpush($1,$2);}

constraint:
	'{' input IMPLIES outputs template '}' {$$ = newconstraint($2,$4);}
	;

input: expr {$$ = $1;} ;

expr:
	  primary
	    {$$=$1;}
	| expr OR expr
	      {$$ = newexpr(XSORT_OR,$1,$3);}
	| expr AND expr
	      {$$ = newexpr(XSORT_AND,$1,$3);}
	| NOT expr %prec NOT
	      {$$ = newexpr(XSORT_NONET,$2,NULL);}
	| '(' expr ')'
	      {$$=$2;}
	;

primary:
	  ident {$$ = newprimary($1);}
	| constant {$$ = newprimary($1);}
	;

outputs:
	  output {$$ = vlistpush(vlistnew(),$1);}
	| outputs ',' output {$$ = vlistpush($1,$3);}
	;

output:
	  ident {$$ = newoutput($1);}
	| '!' output {$$ = outputnot($2);}
	| ident '=' expr {$$ = outputset($1,$3);}
	;

ident: IDENT {$$ = $1;}

path: PACKAGE_PATH {$$ = $1;}

constant:
	  STRING_CONST {$$ = $1;}
	| INTEGER_CONST {$$ = $1;}
	| DOUBLE_CONST {$$ = $1;}
	| boolean_constant {$$ = $1;}

boolean_constant:
	  ON {$$ = TrueConst;}
	| OFF {$$ = FalseConst;}
	| YES {$$ = TrueConst;}
	| NO {$$ = FalseConst;}
	| TRUE {$$ = TrueConst;}
	| FALSE {$$ = FalseConst;}
	;

	;
%%

static Konst
newconstraintid(void)
{
    Konst id;
    char digits[64];
    snprintf(digits,sizeof(digits),"%u",++(globalstate.parser->constraintcounter));
    id = EmptyKonst;
    id.id = strdup(digits);
    return id;
}

static Expr*
newoutput(Konst id)
{
    Expr* res = (Expr*)calloc(1,sizeof(Expr));
    res->sort = XSORT_ID;
    res->value = clonekonst(id);
    return res;
}

static Expr*
outputnot(Expr* expr)
{
    Expr* res = (Expr*)calloc(1,sizeof(Expr));
    res->sort = XSORT_NONET;
    res->lr[0] = expr;
    return res;
}

static Expr*
outputset(Konst id, Expr* Const)
{
    Expr* res = (Expr*)calloc(1,sizeof(Expr));
    res->sort = XSORT_SET;
    res->lr[0] = Const;
    res->value = clonekonst(id);
    return res;
}

static Expr*
newexpr(ExprSort sort, Expr* left, Expr* right)
{
    Expr* expr = (Expr*)calloc(1,sizeof(Expr));
    expr->sort = sort;
    expr->lr[0] = left;
    expr->lr[1] = right;
    return expr;
}

static Expr*
newprimary(Konst k)
{
    Expr* expr = (Expr*)calloc(1,sizeof(Expr));
    expr->sort = k.sort;
    expr->value = clonekonst(k);
}

static Object*
newobject(Sort sort, Konst id)
{
    Object* obj = NULL;
    switch (sort) {
    SORT_OPT: obj = (Object*)calloc(1,sizeof(Option)); break;
    SORT_PROP: obj = (Object*)calloc(1,sizeof(Property)); break;
    SORT_LIB: obj = (Object*)calloc(1,sizeof(Library)); break;
    SORT_CON: obj = (Object*)calloc(1,sizeof(Constraint)); break;
    SORT_EXPR: obj = (Object*)calloc(1,sizeof(Expr)); break;
    default: semerror("Bad Sort"); break;
    }
    obj->sort = sort;
    assert(id.sort == XSORT_ID);
    obj->id = strdup(id.id);
    insertbyname(globalstate.state.allobjects,obj);
    if(obj->sort == SORT_CON) vlistpush(globalstate.state.allconstraints,obj);
    return obj;
}

static Option*
newoption(Konst id, TypeType typ, Expr* expr, Konst template)
{
    Option* opt = (Option*)newobject(SORT_OPT,id);
    opt->typ = typ;
    opt->expr = expr;
    assert(template.sort == XSORT_STRING);
    opt->hdr.template = strdup(template.sval);
    return opt;
}

static Property*
newproperty(Konst id, TypeType typ, Expr* expr, Konst template)
{
    Property* prop = (Property*)newobject(SORT_PROP,id);
    prop->typ = typ;
    prop->expr = expr;
    prop->hdr.template = strdup(template.sval);
    return prop;
}

static Library*
newlibrary(Konst id, Konst path, Konst template)
{
    Library* lib = (Library*)newobject(SORT_LIB,id);
    lib->path = strdup(path.sval);
    lib->hdr.template = strdup(template.sval);
    return lib;
}

static VList*
maptemplate(VList* list, Konst template)
{
    size_t i;
    for(i=0;i<list->length;i++) {
	Object* o = (Object*)vlistget(list,i);
	if(o->template == NULL) {
	    o->template = strdup(template.sval);
	}
    }
    return list;
}

#if 0
static Template*
newtemplate(Konst k)
{
    Template* t = NULL;
    if(k.op != XSORT_STRING)
	semerror("non-string template Const");
    t = (Template*)calloc(1,sizeof(Template));
    t->template = strdup(k.sval);
    return t;
}

static Template*
clonetemplate(Konst template)
{
    Konst k;
    Template* clone = NULL;
    k.op = XSORT_STRING;
    k.sval = strdup(pattern->template);
    clone = newtemplate(k);
    return clone;
}
#endif

static Constraint*
newconstraint(Expr* input, VList* outputs)
{
    Constraint* con = (Constraint*)newobject(SORT_CON,newconstraintid());
    con->input = input;
    con->outputs = outputs;
    return con;
}

/**************************************************/
static void
semerror(const char* msg)
{
    fprintf(stderr,"error: %s\n",msg);
    exit(1);
}

/**************************************************/

#define LEXERROR(msg) cmkerror(&globalstate->lexer->loc, globalstate, msg)

static void
cmkerror(YYLTYPE *locp, GlobalState* globalstate, const char* msg)
{
    fprintf(stderr,"cmaker: error [");
    YYLOCATION_PRINT(stderr,locp);
    fprintf(stderr,"] %s\n",msg);
}

/**************************************************/

/* Lexer constants */
static char* numchars1 = "0123456789.+-";
static char* numcharsn = "0123456789.+-Ee";
static char* kwchars1 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_";
static char* kwcharsn = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-";
static char* hexchars = "abcdefABCDEF0123456789";
static char* delim2chars = "&|";

static struct KeyWord {
    int token;
    const char* word;
} keywords[] = {
    {ON,"on"},
    {YES,"yes"},
    {TRUE,"true"},
    {OFF,"off"},
    {NO,"no"},
    {FALSE,"false"},
    {BOOL_CONST,"bool_const"},
    {STRING_CONST,"string_const"},
    {INTEGER_CONST,"integer_const"},
    {DOUBLE_CONST,"double_const"},
    {IDENT,"ident"},
    {PACKAGE_PATH,"package_path"},
    {BOOL,"bool"},
    {CMAKER,"cmaker"},
    {CONSTRAINTS,"constraints"},
    {DOUBLE,"double"},
    {END,"end"},
    {IMPLIES,"implies"},
    {INTEGER,"integer"},
    {LIBRARIES,"libraries"},
    {LIBRARY,"library"},
    {OPTION,"option"},
    {OPTIONS,"options"},
    {PROPERTIES,"properties"},
    {PROPERTY,"property"},
    {0,NULL},
};

#define LEXCHAR() lexchar(lexer)
#define LEXUNGET(c) lexunget(lexer,c)

static int
lexchar(Lexer* lexer)
{
    lexer->loc.last_column++;
    return getchar();
}

static void
lexunget(Lexer* lexer, int c)
{
    lexer->loc.last_column--;
    ungetc(c,stdin);
}

static int
tohex(int c)
{
    if(c >= 'a' && c <= 'f') return (c - 'a') + 0xa;
    if(c >= 'A' && c <= 'F') return (c - 'A') + 0xa;
    if(c >= '0' && c <= '9') return (c - '0');
    return -1;
}

static const char*
token_name(int t) {
    return yysymbol_name(YYTRANSLATE(t));
}

static void
dumptoken(struct Lexer* lexer)
{
    switch (lexer->token) {
    case IDENT: case STRING_CONST:
	fprintf(stderr,"TOKEN: %s = |\"%s\"|\n",
		token_name(lexer->token), lexer->value.sval);
	break;
    case INTEGER_CONST:
	fprintf(stderr,"TOKEN: %s = |%lld|\n",
		token_name(lexer->token), lexer->value.ival);
	break;
    case DOUBLE_CONST:
	fprintf(stderr,"TOKEN: %s = |%lg|\n",
		token_name(lexer->token), lexer->value.dval);
	break;
    default:
	fprintf(stderr,"TOKEN: '%s'\n",token_name(lexer->token));
	break;
    }
}

static int
cmklex(YYSTYPE* lvalp, YYLTYPE* llocp, GlobalState* globalstate)
{
    int token;
    int c;
    char* p=NULL;
    Lexer* lexer = globalstate->lexer;

    /* Setup */
    lexer->loc = *llocp;
    token = 0;
    lexer->value = EmptyKonst;
    vssetlength(lexer->yytext,0);
    /* Look for next meaningful token */
    while(token == 0) {
	if(c <= ' ' || c >= '\177') {c=LEXCHAR(); continue;}
	/* See if we have a two char delimiter */
	if(c == '&') {
	    if((c = LEXCHAR()) == '&') {token = AND; break;}
	    LEXUNGET(c); c = '&';
	}
	if(c == '|') {
	    if((c = LEXCHAR()) == '|') {token = OR; break;}
	    LEXUNGET(c); c = '|';
	}
	if(c == '"') {
	    int more = 1;
	    vsappend(lexer->yytext,c);
	    /* We have a STRING_CONST */
	    while(more && (c=LEXCHAR())) {
		switch (c) {
		case '"': LEXCHAR(); more=0; break;
		case '\\':
		    c = LEXCHAR();
		    switch (c) {
		    case 'r': c = '\r'; break;
		    case 'n': c = '\n'; break;
		    case 'f': c = '\f'; break;
		    case 't': c = '\t'; break;
		    case 'x': {
			int d1,d2;
			c = LEXCHAR();
			d1 = tohex(c);
			if(d1 < 0) {
			    LEXERROR("Illegal \\xDD in SCAN_STRING");
			} else {
			    c = LEXCHAR();
			    d2 = tohex(c);
			    if(d2 < 0) {
				LEXERROR("Illegal \\xDD in SCAN_STRING");
			    } else {
				c=(int)((((unsigned int)d1)<<4) | (unsigned int)d2);
			    }
			}
		    } break;
		    default: break;
		    }
		    break;
		default: break;
		}
		vsappend(lexer->yytext,c);
	    }
	    token = STRING_CONST;
	    lexer->value.sort = XSORT_STRING;
	    lexer->value.sval = vsextract(lexer->yytext);
	} else if(strchr(numchars1,c) != NULL) {
	    /* we might have a INTEGER_CONST or DOUBLE_CONST */
	    char* text;
	    char* endpoint;
	    int ishex = 0;
	    vsappend(lexer->yytext,c);
	    /* Preemptive check for hex */
	    if(c == '0') {
		c = LEXCHAR();
		if(c == 'x' || c == 'X') {
		    /* Assume it is hex */
		    vssetlength(lexer->yytext,0);
		    for(;;) {
			c = LEXCHAR();
			if(strchr(hexchars,c) == NULL) break;
			vsappend(lexer->yytext,c);
		    }
		    text = vscontents(lexer->yytext);
		    /* See if scanf can parse as hex */
		    if(1==scanf(text,"%ullx",(unsigned long long*)&lexer->value.ival)) {
			token = INTEGER_CONST;
		    } else {
			LEXERROR("Illegal hex Const");
		    }
		} else {
		    LEXUNGET(c); /* pushback the x */
		}
		ishex = 1;
	    }
	    if(!ishex) {
		for(;;) {
		    c = LEXCHAR();
		    if(strchr(numcharsn,c) == NULL) break;
		    vsappend(lexer->yytext,c);
		}
		text = vscontents(lexer->yytext);
		/* See if scanf can parse as integer */
		if(1==scanf(text,"%lld",&lexer->value.ival)) {
		    token = INTEGER_CONST;
		} else { /* Ok see if it scans as a double */
		    if(1==scanf(text,"%lg",&lexer->value.dval))
			token = DOUBLE_CONST;
		    else {
			LEXERROR("Illegal numeric Const");
		    }
		}
	    } else if(strchr(kwchars1,c) != NULL) {
		/* we have a ident or a keyword */
		vsappend(lexer->yytext,c);
		for(;;) {
		    c = LEXCHAR();
		    if(strchr(kwcharsn,c) == NULL) break;
		    vsappend(lexer->yytext,c);
		}
		/* Search for a keyword */
		{
		    char* word = vscontents(lexer->yytext);
		    struct KeyWord* p;
		    token = 0;
		    for(p=keywords;p->token;p++) {
			if(strcasecmp(p->word,word)==0) {
			    token = p->token;
			    break;
			}
		    }
		    if(token == 0) {
			token = IDENT;
			lexer->value.sort = XSORT_ID;
			lexer->value.id = vsextract(lexer->yytext);
		    }
		}
	    } else {
		/* we have a single char token */
		token = c;
		vsappend(lexer->yytext,c);
		LEXCHAR();
	    }
	}
    }
    size_t len = vslength(lexer->yytext);
    lexer->token = token;
    *llocp = lexer->loc;
    lvalp->konst = lexer->value; /*Put return Konst onto Bison stack*/
    if(lexer->debug) dumptoken(lexer);
    return token;
}

/**************************************************/

/**
Topologically sort constraints
@param state
@return the sorted list of constraints
*/
static VList*
toposort(struct State* state)
{
    size_t i,j;
    VList* ordering = vlistnew();
    VList* unsorted = vlistclone(state->allconstraints);
    compute_edges(state->allconstraints);
}

/* 
1. For each constraint:
   - collect the unique set of resources referenced in the input expr.
   - collect the unique set of resources referenced in the output exprs
2. For each constraint a:
    Collect the set of constraints b such that:
	output-resources(a) intersects input-resources(b)
    Effectively this creates (a->b) edges
3. For each option o:
    Collect the set of constraints b where input-resources(b) intersects {o}
*/

static void
compute_edges(VList* allconstraints)
{
    size_t i;
    for(i=0;i<vlistlength(allconstraints);i++) {
	Constraint* a = vlistget(allconstraints,i);
	a->edges = create_edges_for(a,allconstraints);
    }
}

static VList* /*VList<Constraint*>*/
create_edges_for(Constraint* a, VList* allconstraints)
{
    size_t i;
    VList* edges = vlistnew();
    for(i=0;i<vlistlength(allconstraints);i++) {
	Constraint* b = vlistget(allconstraints,i);
	if(a == b) continue;
	if(intersects(a->outputrefs,b->inputrefs))
	    vlistpush(edges,b); /* add edge */
    }
    return edges;    

}

static int
intersects(VList* set1, VList* set2)
{
    size_t i,j;
    for(i=0;i<vlistlength(set1);i++) {
	Expr* ref1 = vlistget(set1,i);
	assert(ref1->sort == XSORT_ID);
	for(j=0;j<vlistlength(set2);j++) {
	    Expr* ref2 = vlistget(set2,j);
	    assert(ref2->sort == XSORT_ID);
	    if(strcmp(ref1->value.id,ref2->value.id)==0) 
		return 1; /* sets intersect */
	}
    }
    return 0; /* Does not intersect */
}

static void
collectrefs(VList* allconstraints)
{
    size_t i,j;
    Constraint* constraint = NULL;
    for(i=0;i<vlistlength(allconstraints);i++) {
	Constraint* constraint = vlistget(allconstraints,i);
	if(constraint->inputrefs == NULL) constraint->inputrefs = vlistnew();
	if(constraint->outputrefs == NULL) constraint->outputrefs = vlistnew();
	/* Collect the refs in the input expression of a constraint */
	walkexpr(constraint->input,(void*)constraint->inputrefs);
	/* Collect the refs in the output expressions of a constraint */
	for(j=0;j<vlistlength(constraint->outputs);j++) {
	    Expr* expr = vlistget(constraint->outputs,j);
	    walkexpr(expr,(void*)constraint->outputrefs);
	}
    }
}

/**************************************************/
/* Utilities */

/* ApplyFcn for Expr walker */
static void
exprapply(Expr* expr, void* state)
{
    VList* refs = (VList*)state;
    switch (expr->sort) {
    case XSORT_ID:
	(void)insertbyptr(refs,(void*)expr);
	break;
    default: break; /*ignore*/
    }
}

/*
Walk an expr depth first and apply function to every node.
@param expr to walk
@param fcn to apply
@param persistent state for fcn
@return void
*/
static void
walkexpr(Expr* expr, void* state)
{
    VList* stack = vlistnew();
    vlistpush(stack,expr);
    /* Repeat until stack is empty */
    while(vlistlength(stack) > 0) {
	Expr* next = (Expr*)vlistpop(stack);
	exprapply(next,state);
	if(next->lr[0] != NULL) vlistpush(stack,next->lr[0]);
	if(next->lr[1] != NULL) vlistpush(stack,next->lr[1]);
    }
}

static Konst
clonekonst(Konst k)
{
    Konst klone;
    klone = EmptyKonst;
    klone = k;
    /* Deep copy strings */
    switch (k.sort) {
    case XSORT_ID: klone.id = strdup(klone.id); break;
    case XSORT_PATH: /*fall thru*/
    case XSORT_STRING: klone.sval = strdup(klone.sval); break;
    default: break; /* No strings involved */
    }
    return klone;
}


static const char*
sortname(Sort sort)
{
    switch (sort) {
    case SORT_OPT:  return "Option";
    case SORT_PROP: return "Property";
    case SORT_LIB:  return "Library";
    case SORT_CON:  return "Constraint";
    case SORT_NONE:
    default: break;
    }
    return "<Unknown>";
}

#if 0
static Ident
identify(const char* idstr)
{
    Ident id;
    const char* p = NULL;
    const char* split = NULL;
    const char namespace[MAX_NAME] = NULL;
    ptrdiff_t count = -1;

    /* locate the :: split point */
    for(p=idstr;*p;p++) {
	if(p[0] == ':' && p[1] == ':')
	    {count = (p - idstr); split = &p[2]; break;}
    }
    if(count <=	 0) {
	namespace[0] = '\0'; /* abcd | ::abcd */
    } else if(count >= MAX_NAME)
	count = (MAX_NAME - 1);
    if(*split == '\0') goto done; /* empty id part e.g. 'xyz::' */
    memset(id,0,sizeof(Ident));
    if(count > 0) memcpy(id->namespace,namespace,count); /*calloc=>nul-term*/
    strncpy(id->id,idstr,MAX_NAME-1); /*calloc=>nul-term*/
done:
    return id;
}
#endif

/**
eqptr Function
Equality is determined by ptr equality
*/
static int
eqptr(void* newelem, void* oldelem)
{
    return (newelem == oldelem ? 1 : 0);
}

/**
eqid Function
This differs from eqptr in that equality
is determined by identifier
*/
static int
eqid(void* newelem, void* oldelem)
{
    Object* newobj = newelem;
    Object* oldobj = oldelem;
    if(strcmp(newobj->id,oldobj->id)==0) return 1; /*match*/
    return 0; /* no match */
}

/**
Insert newelem if not already present in vlist.
@param vl in which to insert
@param newelem to insert
@param eqfcn for equal test
@return the vl argument
*/
static VList*
insertunique(VList* vl, void* newelem, EqualsFcn eqfcn)
{
    size_t i;
    for(i=0;i<vlistlength(vl);i++) {
	void* elem = vlistget(vl,i);
	if(eqfcn(newelem, elem)) goto done;
    }
    /* If we get here, then the element is not a duplicate */
    vlistpush(vl,newelem);
done:
    return vl;
}

/**
Same as insertunique but specifically uses ptr equality.
@param vl in which to insert
@param newelem to insert
@return the vl argument
*/
static VList*
insertbyptr(VList* vl, void* newelem)
{
    return insertunique(vl,newelem,eqptr);
}

/**
Same as insertunique but uses name equality and reports
error if match is found
@param vl in which to insert
@param newelem to insert
@return the vl argument
*/
static VList*
insertbyname(VList* vl, Object* newobj)
{
    size_t i;
    for(i=0;i<vlistlength(vl);i++) {
	Object* oldobj = vlistget(vl,i);
	if(eqid(newobj, oldobj)) {
	    /* Duplicate name => error */
	    char msg[4096];
	    snprintf(msg,sizeof(msg),"%s::%s and %s::%s",
			sortname(oldobj->sort),oldobj->id,
			sortname(newobj->sort),newobj->id);
	    semerror(msg);
	}
    }
    /* If we get here, then the element is not a duplicate */
    vlistpush(vl,newobj);
done:
    return vl;
}


/**************************************************/

static void
usage(void)
{
    fprintf(stderr,"usage: cmaker"
" [-d]"
" [-v]"
" [< input-file]"
" [> output-file]"
"\n");
}

int
main(int argc, char** argv)
{
    int retval = 0;
    int c;

    /* Init options */
    memset((void*)&options,0,sizeof(options));
    while ((c = getopt(argc, argv, "dv")) != EOF) {
	switch(c) {
	case 'd':
	    options.debug = 1;
	    break;
	case 'v':
	    usage();
	    goto done;
	case '?':
	   fprintf(stderr,"unknown option\n");
	   retval = -1;
	   goto done;
	}
    }
    /* get unprocessed argument(s) */
    argc -= optind;
    argv += optind;

    if (argc != 0) {
	retval = -1;
	fprintf(stderr, "cmaker: unexpected extra arguments\n");
	goto done;
    }

    /* Initialize global state */
    memset(&globalstate,0,sizeof(GlobalState));
    globalstate.state.allobjects = vlistnew();

    /* Initialize parser */
    globalstate.parser = calloc(1,sizeof(struct Parser));
    globalstate.parser->constraintcounter = 0;

    /* Initialize lexer */
    globalstate.lexer = calloc(1,sizeof(struct Lexer));
    globalstate.lexer->token = 0;
    globalstate.lexer->yytext = vsnew();

    /* Parse input file */
    if(yyparse(&globalstate)) {retval = -1;}
    if(retval)
	fprintf(stderr,"*** Parse failed.\n");
done:
    return (retval?0:1);
}
