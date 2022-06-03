local list_ext_obj = require 'list_ext_obj'

-- =============================================== --

local sprintf = string.format

local function _make_column_format(columns)
	local col_fmt = {}
	for _, col in ipairs (columns) do
		table.insert(col_fmt, sprintf('%%%ds', col.width/8))
	end
	return table.concat(col_fmt, ' | ')
end


local function _print_header(name)
	local columns = GetColumnDescription(name)
	local col_names = {}
	for _, col in ipairs (columns) do
		table.insert(col_names, col.name)
	end
	local str_header = sprintf(_make_column_format(columns), table.unpack(col_names))
	print(str_header)
	print(string.rep('=', #str_header))
end

local function _print_data(name, psp_path)
	local columns = GetColumnDescription(name)
	local col_fmt = _make_column_format(columns)

	local test_report  = require('test_report')
	test_report(psp_path, nul) -- ,  , {0, 1000000}

	local cnt_row = InitMark(name)
	--SortMarks(6, True)
	for row = 1, cnt_row do
		local values = {}
		for col = 1, #columns do
			local text = GetItemText(row, col)
			table.insert(values, tostring(text))
		end
		local text_row = sprintf(col_fmt, table.unpack(values))
		print(text_row)
	end
end

local function _print_names()
	local names = GetFilterNames()
	for i, n in ipairs(names) do
		print(i, ":", n)
	end
end

-- =============================================== --

--local name = "Записная книжка"
local name = 'Кривые'
local psp_path = 'D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml'

_print_header(name)
_print_data(name, psp_path)
