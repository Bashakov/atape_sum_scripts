require "luacom"

if not ATAPE then
	require "iuplua"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
local mark_helper = require 'sum_mark_helper'
local codecs = require 'process_utf8'
local template = require "resty.template"

require 'ExitScope'

-- ============================================================

local function SaveAndShow(report_rows, dlgProgress, report_template_name, sheet_name)
	if #report_rows > 1000 then
		local msg = string.format('Найдено %d отметок, построение отчета может занять большое время, продолжить?', #report_rows)
		local cont = iup.Alarm("Warning", msg, "Yes", "No")
		if cont == 2 then
			return
		end
	end

	local template_path = Driver:GetAppPath() .. 'Scripts\\'  .. report_template_name
	local ext_psp = mark_helper.GetExtPassport(Passport)
	local excel = excel_helper(template_path, sheet_name, false)

	excel:ApplyPassportValues(ext_psp, dlgProgress)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()
end


local function make_rows(getMarks, dlgProgress, row_generators)
	local code2marks = {} -- убрать дублирование отметок полученных через стандартную функцию отчетов (включающую пользовательские отметки с опр. гуидом) и пользовательскую функцию отчетов
	local report_rows = {}
	local marks = getMarks()

	for _, fn_gen in ipairs(row_generators) do
		local cur_rows = fn_gen(marks, dlgProgress)
		if not cur_rows then
			break
		end
		for _, row in ipairs(cur_rows) do
			local code = row.DEFECT_CODE or ''
			local id = row.mark_id or -1
			if not code2marks[code] then code2marks[code] = {} end
			if id < 0 or not code2marks[code][id] then
				code2marks[code][id] = true
				table.insert(report_rows, row)
			end
		end
	end

	report_rows = mark_helper.sort_stable(report_rows, function(row)
		return row.SYS
	end)
	return report_rows
end

local function make_report_generator(getMarks, report_template_name, sheet_name, ...)
	local row_generators = {...}

	return function()
		return EnterScope(function (defer)
			local dlgProgress = luaiup_helper.ProgressDlg()
			defer(dlgProgress.Destroy, dlgProgress)

			local report_rows = make_rows(getMarks, dlgProgress, row_generators)
			SaveAndShow(report_rows, dlgProgress, report_template_name, sheet_name)
		end)
	end
end

local function make_html_generator(getMarks, html_template_name, dst_prefix, report_name, ...)
	local row_generators = {...}

	return function()
		return EnterScope(function (defer)
			local dlgProgress = luaiup_helper.ProgressDlg()
			defer(dlgProgress.Destroy, dlgProgress)

			local rows = make_rows(getMarks, dlgProgress, row_generators)

			local path_template = Driver:GetAppPath() .. 'Scripts\\'  .. html_template_name
			local user_dir = os.getenv('USERPROFILE') -- возвращает путь кодированный в cp1251, что вызывает ошибку при копировании, тк ожидается utf-8
			user_dir = codecs.cp1251_utf8(user_dir)
			local path_dst = user_dir .. '\\ATapeReport\\' .. dst_prefix .. os.date('%y%m%d-%H%M%S') .. ".html"

			local view = template.new(path_template)
			view.psp = mark_helper.GetExtPassport(Passport)
			view.rows = rows
			view.report_name = report_name
			local strHtml = tostring(view)
			local f = assert(io.open(path_dst, "w+"))
			f:write(strHtml)
			f:close()
			os.execute('explorer ' .. path_dst)
		end)
	end
end


local function IsAvailable()
	return EKASUI
end

-- ===========================================================

return {
	make_report_generator = make_report_generator,
	make_html_generator = make_html_generator,
	IsAvailable = IsAvailable,
}
