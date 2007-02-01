#!/usr/bin/python
#    This is 'comp', a tool to write HAL boilerplate
#    Copyright 2006 Jeff Epler <jepler@unpythonic.net>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

import os, sys, tempfile, shutil, getopt, time
BASE = os.path.abspath(os.path.join(os.path.dirname(sys.argv[0]), ".."))
sys.path.insert(0, os.path.join(BASE, "lib", "python"))

%%
parser Hal:
    ignore: "//.*"
    ignore: "/[*](.|\n)*?[*]/"
    ignore: "[ \t\r\n]+"

    token END: ";;"
    token PARAMDIRECTION: "rw|r"
    token PINDIRECTION: "in|out|io"
    token TYPE: "float|bit|signed|unsigned|u32|s32"
    token NAME: "[a-zA-Z_][a-zA-Z0-9_]*"
    token FPNUMBER: "-?([0-9]*\.[0-9]+|[0-9]+\.?)([Ee][+-]?[0-9]+)?f?"
    token NUMBER: "-?[0-9]+|0x[0-9a-fA-F]+"
    token STRING: '"(\\.|[^\\"])*"'
    token TSTRING: '"""(\\.|\\\n|[^\\"]|"(?!"")|\n)*"""'

    rule File: Declaration* "$" {{ return True }}
    rule Declaration:
        "component" NAME OptString";" {{ comp(NAME, OptString); }}
      | "pin" PINDIRECTION TYPE NAME OptAssign OptString ";"  {{ pin(NAME, TYPE, PINDIRECTION, OptString, OptAssign) }}
      | "param" PARAMDIRECTION TYPE NAME OptAssign OptString ";" {{ param(NAME, TYPE, PARAMDIRECTION, OptString, OptAssign) }}
      | "function" NAME OptFP OptString ";"       {{ function(NAME, OptFP, OptString) }}
      | "option" NAME OptValue ";"   {{ option(NAME, OptValue) }}
      | "see_also" String ";"   {{ see_also(String) }}
      | "description" String ";"   {{ description(String) }}

    rule String: TSTRING {{ return eval(TSTRING) }} 
            | STRING {{ return eval(STRING) }}
 
    rule OptString: TSTRING {{ return eval(TSTRING) }} 
            | STRING {{ return eval(STRING) }}
            | {{ return '' }}
    rule OptAssign: "=" Value {{ return Value; }}
                | {{ return None }}
    rule OptFP: "fp" {{ return 1 }} | "nofp" {{ return 0 }} | {{ return 1 }}
    rule Value: "yes" {{ return 1 }} | "no" {{ return 0 }}  
                | "true" {{ return 1 }} | "false" {{ return 0 }}  
                | "TRUE" {{ return 1 }} | "FALSE" {{ return 0 }}  
                | NAME {{ return NAME }}
                | FPNUMBER {{ return float(FPNUMBER.rstrip("f")) }}
                | NUMBER {{ return int(NUMBER,0) }}
    rule OptValue: Value {{ return Value }}
                | {{ return 1 }}
%%

def parse(rule, text, filename=None):
    global P, S
    S = HalScanner(text, filename=filename)
    P = Hal(S)
    return runtime.wrap_error_reporter(P, rule)

dirmap = {'r': 'HAL_RO', 'rw': 'HAL_RW', 'in': 'HAL_IN', 'out': 'HAL_OUT', 'io': 'HAL_IO' }
typemap = {'signed': 's32', 'unsigned': 'u32'}
deprmap = {'s32': 'signed', 'u32': 'unsigned'}
deprecated = ['s32', 'u32']

def initialize():
    global functions, params, pins, options, comp_name, names, docs

    functions = []; params = []; pins = []; options = {}
    docs = []
    comp_name = None

    names = {}

def Warn(msg, *args):
    if args:
        msg = msg % args
    print >>sys.stderr, "%s:%d: Warning: %s" % (S.filename, S.line, msg)

def Error(msg, *args):
    if args:
        msg = msg % args
    raise runtime.SyntaxError(S.get_pos(), msg, None)

def comp(name, doc):
    docs.append(('component', name, doc))
    global comp_name
    if comp_name:
        Error("Duplicate specification of component name")
    comp_name = name;

def description(doc):
    docs.append(('descr', doc));

def see_also(doc):
    docs.append(('see_also', doc));

def type2type(type):
    # When we start warning about s32/u32 this is where the warning goes
    return typemap.get(type, type)
    
def pin(name, type, dir, doc, value):
    type = type2type(type)
    if name in names:
        Error("Duplicate item name %s" % name)
    docs.append(('pin', name, type, dir, doc, value))
    names[name] = None
    pins.append((name, type, dir, value))

def param(name, type, dir, doc, value):
    type = type2type(type)
    if name in names:
        Error("Duplicate item name %s" % name)
    docs.append(('param', name, type, dir, doc, value))
    names[name] = None
    params.append((name, type, dir, value))

def function(name, fp, doc):
    if name in names:
        raise runtime.SyntaxError, "Duplicate item name %s" % name
    docs.append(('funct', name, fp, doc))
    names[name] = None
    functions.append((name, fp))

def option(name, value):
    if name in options:
        raise runtime.SyntaxError, "Duplicate option name %s" % name
    options[name] = value

def removeprefix(s,p):
    if s.startswith(p): return s[len(p):]
    return s

def to_hal(name):
    return name.replace("_", "-").rstrip("-").rstrip(".")

def prologue(f):
    print >> f, "/* Autogenerated by %s on %s -- do not edit */" % (
        sys.argv[0], time.asctime())
    print >> f, """\
#include "rtapi.h"
#include "rtapi_app.h"
#include "hal.h"
#include "rtapi_string.h"

static int comp_id;
"""
    names = {}

    def q(s):
        s = s.replace("\\", "\\\\")
        s = s.replace("\"", "\\\"")
        s = s.replace("\r", "\\r")
        s = s.replace("\n", "\\n")
        s = s.replace("\t", "\\t")
        s = s.replace("\v", "\\v")
        return '"%s"' % s

    print >>f, "#ifdef MODULE_INFO"
    for v in docs:
        if not v: continue
        v = ":".join(map(str, v))
        print >>f, "MODULE_INFO(emc2, %s);" % q(v)
    print >>f, "#endif // __MODULE_INFO"
    print >>f

    has_data = options.get("data")

    print >>f
    print >>f, "struct state {"
    print >>f, "    struct state *_next;"
    for name, type, dir, value in pins:
        if names.has_key(name):
            raise RuntimeError, "Duplicate item name: %s" % name
        print >>f, "    hal_%s_t *%s;" % (type, name)
        names[name] = 1

    for name, type, dir, value in params:
        if names.has_key(name):
            raise RuntimeError, "Duplicate item name: %s" % name
        print >>f, "    hal_%s_t %s;" % (type, name)
        names[name] = 1

    if has_data:
        print >>f, "    void *_data;"

    print >>f, "};"

    if options.get("userspace"):
        print >>f, "#include <stdlib.h>"

    print >>f, "struct state *inst=0;"
    print >>f, "struct state *first_inst=0;"
    
    print >>f
    for name, fp in functions:
        if names.has_key(name):
            raise RuntimeError, "Duplicate item name: %s" % name
        print >>f, "static void %s(struct state *inst, long period);" % name
        names[name] = 1

    print >>f, "static int get_data_size(void);"
    if options.get("extra_setup"):
        print >>f, "static int extra_setup(struct state *inst, long extra_arg);"
    if options.get("extra_cleanup"):
        print >>f, "static void extra_cleanup(void);"

    print >>f
    print >>f, "static int export(char *prefix, long extra_arg) {"
    print >>f, "    char buf[HAL_NAME_LEN + 2];"
    print >>f, "    int r = 0;"
    print >>f, "    int sz = sizeof(struct state) + get_data_size();"
    print >>f, "    struct state *inst = hal_malloc(sz);"
    print >>f, "    memset(inst, 0, sz);"
    if options.get("extra_setup"):
	print >>f, "    r = extra_setup(inst, extra_arg);"
	print >>f, "    if(r != 0) return r;"

    for name, type, dir, value in pins:
        print >>f, "    r = hal_pin_%s_newf(%s, &(inst->%s), comp_id," % (
            type, dirmap[dir], name)
        print >>f, "        \"%%s%s\", prefix);" % to_hal("." + name)
        print >>f, "    if(r != 0) return r;"
        if value is not None:
            print >>f, "    *(inst->%s) = %s;" % (name, value)

    for name, type, dir, value in params:
        print >>f, "    r = hal_param_%s_newf(%s, &(inst->%s), comp_id," % (
            type, dirmap[dir], name)
        print >>f, "        \"%%s%s\", prefix);" % to_hal("." + name)
        if value is not None:
            print >>f, "    inst->%s = %s;" % (name, value)
        print >>f, "    if(r != 0) return r;"

    for name, fp in functions:
        print >>f, "    rtapi_snprintf(buf, HAL_NAME_LEN, \"%%s%s\", prefix);"\
            % to_hal("." + name)
        print >>f, "    r = hal_export_funct(buf, (void(*)(void *inst, long))%s, inst, %s, 0, comp_id);" % (
            name, int(fp))
        print >>f, "    if(r != 0) return r;"
    print >>f, "    inst->_next = first_inst;"
    print >>f, "    first_inst = inst;"
    print >>f, "    return 0;"
    print >>f, "}"

    if options.get("count_function"):
        print >>f, "static int get_count(void);"

    if options.get("rtapi_app", 1):
        if options.get("constructable") and not options.get("singleton"):
            print >>f, "static int export_1(char *prefix, char *argstr) {"
            print >>f, "    int arg = simple_strtol(argstr, NULL, 0);"
            print >>f, "    return export(prefix, arg);"
            print >>f, "}"   
        if not options.get("singleton") and not options.get("count_function") :
            print >>f, "static int count = %s;" \
                % options.get("default_count", 1)
            if not options.get("userspace"):
                print >>f, "RTAPI_MP_INT(count, \"number of %s\");" % comp_name

        print >>f, "int rtapi_app_main(void) {"
        print >>f, "    int r = 0;"
        if not options.get("singleton"):
            print >>f, "    int i;"
        if options.get("count_function"):
            print >>f, "    int count = get_count();"

        print >>f, "    comp_id = hal_init(\"%s\");" % comp_name
        print >>f, "    if(comp_id < 0) return comp_id;"

        if options.get("singleton"):
            print >>f, "    r = export(\"%s\", 0);" % \
                    to_hal(removeprefix(comp_name, "hal_"))
        else:
            print >>f, "    for(i=0; i<count; i++) {"
            print >>f, "        char buf[HAL_NAME_LEN + 2];"
            print >>f, "        rtapi_snprintf(buf, HAL_NAME_LEN, " \
                                        "\"%s.%%d\", i);" % \
                    to_hal(removeprefix(comp_name, "hal_"))
            print >>f, "        r = export(buf, i);"
            print >>f, "        if(r != 0) break;"
            print >>f, "    }"
        if options.get("constructable") and not options.get("singleton"):
            print >>f, "    hal_set_constructor(comp_id, export_1);"
        print >>f, "    if(r) {"
	if options.get("extra_cleanup"):
            print >>f, "    extra_cleanup();"
        print >>f, "        hal_exit(comp_id);"
        print >>f, "    } else {"
        print >>f, "        hal_ready(comp_id);"
        print >>f, "    }"
        print >>f, "    return r;";
        print >>f, "}"

        print >>f
        print >>f, "void rtapi_app_exit(void) {"
	if options.get("extra_cleanup"):
            print >>f, "    extra_cleanup();"
        print >>f, "    hal_exit(comp_id);"
        print >>f, "}"

    if options.get("userspace"):
        print >>f, "static void user_mainloop(void);"
        if options.get("userinit"):
            print >>f, "static void user_init(int argc, char **argv);"
        print >>f, "int argc=0; char **argv=0;"
        print >>f, "int main(int argc_, char **argv_) {"    
        print >>f, "    argc = argc_; argv = argv;"
        print >>f 
        if options.get("userinit", 0):
            print >>f, "    userinit(argc, argv)";
        print >>f 
        print >>f, "    if(rtapi_app_main() < 0) return 1;"
        print >>f, "    user_mainloop();"
        print >>f, "    rtapi_app_exit();"
        print >>f, "    return 0;"
        print >>f, "}"

    print >>f
    if not options.get("no_convenience_defines"):
        print >>f, "#define FUNCTION(name) static void name(struct state *inst, long period)"
        print >>f, "#define EXTRA_SETUP() static int extra_setup(struct state *inst, long extra_arg)"
        print >>f, "#define EXTRA_CLEANUP() static void extra_cleanup(void)"
        print >>f, "#define fperiod (period * 1e-9)"
        for name, type, dir, value in pins:
            if dir == 'in':
                print >>f, "#define %s (0+*inst->%s)" % (name, name)
            else:
                print >>f, "#define %s (*inst->%s)" % (name, name)
        for name, type, dir, value in params:
            print >>f, "#define %s (inst->%s)" % (name, name)
        
        if has_data:
            print >>f, "#define data (*(%s*)&(inst->_data))" % options['data']

        if options.get("userspace"):
            print >>f, "#define FOR_ALL_INSTS() for(inst = first_inst; inst; inst = inst->_next)"    
    print >>f
    print >>f

def epilogue(f):
    data = options.get('data')
    print >>f
    if data:
        print >>f, "static int get_data_size(void) { return sizeof(%s); }" % data
    else:
        print >>f, "static int get_data_size(void) { return 0; }"

INSTALL, COMPILE, PREPROCESS, DOCUMENT = range(4)

modinc = None
def find_modinc():
    global modinc
    if modinc: return modinc
    d = os.path.abspath(os.path.dirname(os.path.dirname(sys.argv[0])))
    for e in ['src', 'etc/emc2', '/etc/emc2']:
        e = os.path.join(d, e, 'Makefile.modinc')
        if os.path.exists(e):
            modinc = e
            return e
    raise SystemExit, "Unable to locate Makefile.modinc"

def build_usr(tempdir, filename, mode, origfilename):
    binname = os.path.basename(os.path.splitext(filename)[0])

    makefile = os.path.join(tempdir, "Makefile")
    f = open(makefile, "w")
    print >>f, "%s: %s" % (binname, filename)
    print >>f, "\t$(CC) $(EXTRA_CFLAGS) -URTAPI -DULAPI -O2 %s -o $@ $< -Wl,-rpath,$(LIBDIR) -L$(LIBDIR) -lemchal %s" % (
        options.get("extra_compile_args", ""),
        options.get("extra_link_args", ""))
    print >>f, "include %s" % find_modinc()
    f.close()
    result = os.system("cd %s; make -S %s" % (tempdir, binname))
    if result != 0:
        raise SystemExit, result
    output = os.path.join(tempdir, binname)
    if mode == INSTALL:
        shutil.copy(output, os.path.join(BASE, "bin", binname))
    elif mode == COMPILE:
        shutil.copy(output, os.path.join(os.path.dirname(origfilename),binname))

def build_rt(tempdir, filename, mode, origfilename):
    objname = os.path.basename(os.path.splitext(filename)[0] + ".o")
    makefile = os.path.join(tempdir, "Makefile")
    f = open(makefile, "w")
    print >>f, "obj-m += %s" % objname
    print >>f, "include %s" % find_modinc()
    print >>f, "EXTRA_CFLAGS += -I%s" % os.path.abspath(os.path.dirname(origfilename))
    f.close()
    if mode == INSTALL:
        target = "modules install"
    else:
        target = "modules"
    result = os.system("cd %s; make -S %s" % (tempdir, target))
    if result != 0:
        raise SystemExit, result
    if mode == COMPILE:
        for extension in ".ko", ".so", ".o":
            kobjname = os.path.splitext(filename)[0] + extension
            if os.path.exists(kobjname):
                shutil.copy(kobjname, os.path.basename(kobjname))
                break
        else:
            raise SystemExit, "Unable to copy module from temporary directory"

def finddoc(section=None, name=None):
    for item in docs:
        if ((section == None or section == item[0]) and
                (name == None or name == item[1])): return item
    return None

def finddocs(section=None, name=None):
    for item in docs:
        if ((section == None or section == item[0]) and
                (name == None or name == item[1])):
                    yield item

def to_hal_man(s):
    if options.get("singleton"):
        s = "%s.%s" % (comp_name, s)
    else:
        s = "%s.\\fIN\\fB.%s" % (comp_name, s)
    s = s.replace("_", "-")
    s = s.rstrip("-")
    s = s.rstrip(".")
    # s = s.replace("-", "\\-")
    return s

def document(filename, outfilename):
    if outfilename is None:
        outfilename = os.path.splitext(filename)[0] + ".9"

    initialize()
    f = open(filename).read()
    a, b = f.split("\n;;\n", 1)

    p = parse('File', a, filename)
    if not p: raise SystemExit, 1

    f = open(outfilename, "w")

    print >>f, ".TH %s \"9\" \"%s\" \"EMC Documentation\" \"HAL Component\"" % (
        comp_name.upper(), time.strftime("%F"))
    print >>f, ".de TQ\n.br\n.ns\n.TP \\\\$1\n..\n"

    print >>f, ".SH NAME\n"
    doc = finddoc('component')    
    if doc and doc[2]:
        if '\n' in doc[2]:
            firstline, rest = doc[2].split('\n', 1)
        else:
            firstline = doc[2]
            rest = ''
        print >>f, "%s \\- %s" % (doc[1], firstline)
    else:
        rest = ''
        print >>f, "%s" % doc[1]


    print >>f, ".SH SYNOPSIS"
    if options.get("userspace"):
        print >>f, ".B %s" % comp_name
    else:
        if rest:
            print >>f, rest
        elif options.get("singleton") or options.get("count_function"):
            print >>f, ".B loadrt %s" % comp_name
        else:
            print >>f, ".B loadrt %s [count=\\fIN\\fB]" % comp_name
        if options.get("constructable") and not options.get("singleton"):
            print >>f, ".PP\n.B newinst %s \\fIname\\fB" % comp_name

        print >>f, ".SH FUNCTIONS"
        for _, name, fp, doc in finddocs('funct'):
            print >>f, ".TP"
            print >>f, "\\fB%s\\fR" % to_hal_man(name),
            if fp:
                print >>f, "(uses floating-point)"
            else:
                print >>f
            print >>f, doc

    doc = finddoc('descr')    
    if doc and doc[1]:
        print >>f, ".SH DESCRIPTION\n"
        print >>f, "%s" % doc[1]

    lead = ".TP"
    print >>f, ".SH PINS"
    for _, name, type, dir, doc, value in finddocs('pin'):
        print >>f, lead
        print >>f, ".B %s\\fR" % to_hal_man(name),
        print >>f, type, dir,
        if value:
            print >>f, "\\fR(default: \\fI%s\\fR)" % value
        else:
            print >>f, "\\fR"
        if doc:
            print >>f, doc
            lead = ".TP"
        else:
            lead = ".TQ"

    lead = ".TP"
    if params:
        print >>f, ".SH PARAMETERS"
        for _, name, type, dir, doc, value in finddocs('param'):
            print >>f, lead
            print >>f, ".B %s\\fR" % to_hal_man(name),
            print >>f, type, dir,
            if value:
                print >>f, "\\fR(default: \\fI%s\\fR)" % value
            else:
                print >>f, "\\fR"
            if doc:
                print >>f, doc
                lead = ".TP"
            else:
                lead = ".TQ"

    doc = finddoc('see_also')    
    if doc and doc[1]:
        print >>f, ".SH SEE ALSO\n"
        print >>f, "%s" % doc[1]

def process(filename, mode, outfilename):
    tempdir = tempfile.mkdtemp()
    try:
        if outfilename is None:
            if mode == PREPROCESS:
                outfilename = os.path.splitext(filename)[0] + ".c"
            else:
                outfilename = os.path.join(tempdir,
                    os.path.splitext(os.path.basename(filename))[0] + ".c")

        initialize()

        f = open(filename).read()
        a, b = f.split("\n;;\n", 1)

        p = parse('File', a, filename)
        if not p: raise SystemExit, 1

        f = open(outfilename, "w")

        if options.get("userspace"):
            if functions:
                raise SystemExit, "Userspace components may not have functions"
        else:
            if not functions:
                raise SystemExit, "Realtime component must have at least one function"
        if not pins:
            raise SystemExit, "Component must have at least one pin"
        prologue(f)
        lineno = a.count("\n") + 3
        f.write("#line %d \"%s\"\n" % (lineno, filename))
        f.write(b)
        epilogue(f)
        f.close()

        if mode != PREPROCESS:
            if options.get("userspace"):
                build_usr(tempdir, outfilename, mode, filename)
            else:
                build_rt(tempdir, outfilename, mode, filename)

    finally:
        shutil.rmtree(tempdir) 

def usage(exitval=0):
    print """%(name)s: Build, compile, and install EMC HAL components

Usage:
    %(name)s [--install|--compile|--preprocess|--document] compfile...
    %(name)s [--install|--compile] cfile...
""" % {'name': os.path.basename(sys.argv[0])}
    raise SystemExit, exitval

def main():
    mode = PREPROCESS
    outfile = None
    try:
        opts, args = getopt.getopt(sys.argv[1:], "icpdo:h?",
                           ['install', 'compile', 'preprocess', 'outfile=',
                            'document', 'help'])
    except getopt.GetoptError:
        usage(1)

    for k, v in opts:
        if k in ("-i", "--install"):
            mode = INSTALL
        if k in ("-c", "--compile"):
            mode = COMPILE
        if k in ("-p", "--preprocess"):
            mode = PREPROCESS
        if k in ("-d", "--document"):
            mode = DOCUMENT
        if k in ("-o", "--outfile"):
            if len(args) != 1:
                raise SystemExit, "Cannot specify -o with multiple input files"
            outfile = v 
        if k in ("-?", "-h", "--help"):
            usage(0)

    if outfile and mode != PREPROCESS and mode != DOCUMENT:
        raise SystemExit, "Can only specify -o when preprocessing or documenting"

    for f in args:
        if f.endswith(".comp") and mode == DOCUMENT:
            document(f, outfile)            
        elif f.endswith(".comp"):
            process(f, mode, outfile)
        elif f.endswith(".c") and mode != PREPROCESS:
            tempdir = tempfile.mkdtemp()
            try:
                shutil.copy(f, tempdir)
                build(tempdir, os.path.join(tempdir, os.path.basename(f)), mode, f)
            finally:
                shutil.rmtree(tempdir) 
        else:
            raise SystemExit, "Unrecognized file type: %s" % f

if __name__ == '__main__':
    main()

# vim:sw=4:sts=4:et
