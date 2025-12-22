#!/usr/bin/env python3

import re, subprocess, os

include = "/usr/include/"

decls: list[str] = []

gen: dict[str, str] = {
	"atomtype": "c_int",
	"int": "usize",
}

cnv: dict[str, str] = {
	"array": "Array",
	"dataslot": "DataSlot",
	"glist": "GList",
	"parentwidgetbehavior": "ParentWidgetBehavior",
	"template": "Template",
	"widgetbehavior": "WidgetBehavior",
}
decls += [f"const {v} = cnv.{v};" for v in cnv.values()]

cnv_fn: dict[str, str] = {
	"glistkeyfn": "GListKeyFn",
	"glistmotionfn": "GListMotionFn",
}
decls += [f"const {v} = cnv.{v};" for v in cnv_fn.values()]

iem: dict[str, str] = {
	"iem_fstyle_flags": "FontStyleFlags",
	"iem_init_symargs": "InitSymArgs",
	"iemgui": "Gui",
	"iemgui_drawfunctions": "DrawFunctions",
}
decls += [f"const {v} = iem.{v};" for v in iem.values()]

imp: dict[str, str] = {
	"class": "Class",
}
decls += [f"const {v} = imp.{v};" for v in imp.values()]

pd: dict[str, str] = {
	"atom": "Atom",
	"binbuf": "BinBuf",
	"clock": "Clock",
	"float": "Float",
	"floatarg": "Float",
	"garray": "GArray",
	"gobj": "GObj",
	"gpointer": "GPointer",
	"gstub": "GStub",
	"pd": "Pd",
	"sample": "Sample",
	"symbol": "Symbol",
	"text": "Object",
}
decls += [f"const {v} = pd.{v};" for v in pd.values()]

pd_fn: dict[str, str] = {
	"classfreefn": "ClassFreeFn",
	"guicallbackfn": "GuiCallbackFn",
	"method": "Method",
	"newmethod": "NewMethod",
	"perfroutine": "PerfRoutine",
	"propertiesfn": "PropertiesFn",
	"savefn": "SaveFn",
}
decls += [f"const {v} = pd.{v};" for v in pd_fn.values()]

vec_names = ["argv", "av", "vec"]

# Types should be TitleCase and referential to our tailored zig definitions
r_type = r"([^\w])(?:struct__|t_|union_)(\w+)"
def re_type(m):
	name = m.group(2)
	if name in gen: name = gen[name]
	elif name in cnv: name = cnv[name]
	elif name in cnv_fn: name = "*const " + cnv_fn[name]
	elif name in iem: name = iem[name]
	elif name in imp: name = imp[name]
	elif name in pd: name = pd[name]
	elif name in pd_fn: name = "*const " + pd_fn[name]
	return m.group(1) + name

r_ret = r"(?:\[\*c\])(const )?([\w\.]+)"
def re_ret(m):
	typ = m.group(2)
	p = "[*:0]" if typ == "u8" else "*"
	return p + (m.group(1) or "") + typ

# Assume pointers aren't intended to be optional except in special cases,
# and assume char pointers are supposed to be null-terminated strings
r_param = r"(\w+): (?:\[\*c\]|\?\*)(const )?([\w\.]+)"
def re_param(m):
	name = m.group(1)
	typ = m.group(3)
	p = None
	for vec in vec_names:
		if name.endswith(vec):
			p = "[*]"
			break
	if p is None:
		p = "[*:0]" if typ == "u8" else "*"
	return m.group(1) + ": " + p + (m.group(2) or "") + typ

# Assume double pointer is an array pointer or a symbol pointer
# (this is probably wrong sometimes and should eventually be changed)
r_dblptr = r"\[\*c\]\[\*c\](const )?([\w\.]+)"
def re_dblptr(m):
	ptr = "**" if m.group(2) == "pd.Symbol" else "*[*]"
	return ptr + (m.group(1) or "") + m.group(2)


################################################################################
# Main
if __name__ == "__main__":
	lines: list[str]

	# Zig's C-translator does not like bit fields (for now)
	with open(include + "m_pd.h", "r") as f:
		lines = f.read().splitlines()
		for i in range(len(lines)):
			if lines[i].startswith("    unsigned int te_type:2;"):
				lines[i] = "    unsigned char te_type;"
			elif lines[i].startswith("PD_DEPRECATED"):
				lines[i] = ""
	lines += [
		"#include <pd/m_imp.h>",
		"#include <pd/g_canvas.h>",
		"#include <pd/g_all_guis.h>",
		"#include <pd/s_stuff.h>",
	]
	with open("m_pd.h", "w") as f:
		f.write("\n".join(lines))

	# Translate to zig
	out = subprocess.check_output([
		"zig", "translate-c",
		"-isystem", include,
		"m_pd.h",
	], encoding="utf-8")

	# Make some alterations to the translated file
	lines = out.splitlines()
	for i in range(len(lines)):
		if re.match(r"(pub extern fn|pub const \w+ = \?\*const fn)", lines[i]):
			m = re.match(r"(.*)\((?!\.)(.*)\)(.*)", lines[i])
			if m:
				ret = re.sub(r_type, re_type, m.group(3))
				ret = re.sub(r_ret, re_ret, ret)
				args = re.sub(r_type, re_type, m.group(2))
				args = re.sub(r_param, re_param, args)
				args = re.sub(r_dblptr, re_dblptr, args)
				lines[i] = m.group(1) + "(" + args + ")" + ret
		elif re.match(r"pub const t_(\w+) = struct__(\w+)", lines[i]):
			lines[i] = re.sub(r"([^\w])(?:struct__|union_)(\w+)", re_type, lines[i])

	with open("cdef.zig", "w") as f:
		f.write(
			'const pd = @import("pd.zig");\n' +
			'const imp = @import("imp.zig");\n' +
			'const cnv = @import("canvas.zig");\n' +
			'const iem = @import("all_guis.zig");\n' +
			'const stf = @import("stuff.zig");\n' +
			'\n'.join(decls) + '\n' +
			'\n'.join(lines)
		)
	os.remove("m_pd.h")
