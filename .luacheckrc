
-- This file itself
files[".luacheckrc"].ignore = {"111", "112", "131"}

files["DrawVideoDefect_defects.lua"] = {
    read_globals = {"make_recog_mark", "make_simple_defect", "make_group_defect", "make_jat_defect"},
    ignore = {"631"}
}

files["DrawVideoDefect.lua"] = {
    ignore = {"631"}
}

files["sum_list_pane_*.lua"] = {
    global = {
        "work_marks_list",
    }
}

filesp["test_*.lua"] = {
    ignore = {'lowercase-global'}
}

read_globals = {
    "luacom",
    "bit32",
    "iup",
    "MarkTable",
    "Driver",
}

globals = {
    "ATAPE",
    "HUN",
}

exclude_files = {
    ".luacheckrc",
    "luaunit.lua",
    "mobdebug.lua",
    "xml_parse.lua",
}
