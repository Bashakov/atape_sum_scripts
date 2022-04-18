-- https://www.excelforum.com/excel-programming-vba-macros/362364-excel-process-stays-in-memory-after-using-quit-function.html

--print(package.cpath)
--package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'
--print(package.cpath)

local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
local sumPOV = require "sumPOV"
require "ExitScope"


_G.TEST_EXCEL_DST_PATH = "c:\\1"

local function errorf(s,...)  error(string.format(s, ...)) end
local function sprintf(s,...) return string.format(s, ...) end

local function Sleep(seconds)
	for i = 1, seconds do
		os.execute("%COMSPEC% /c ping -n 1 -w 1000 172.26.100.100>nul")
	end
end

local function is_runned()
	return os.execute('C:\\Windows\\SysWOW64\\tasklist.exe | find "EXCEL.EXE"')
end

local function kill_excel()
	os.execute("D:\\Distrib\\SysInternals\\pskill.exe excel")
end

kill_excel()

local template_path =  'C:/Program Files (x86)/ATapeXP/Scripts/СВОДНАЯ ВЕДОМОСТЬ ОТСТУПЛЕНИЙ.xlsx'

local function ff()
	local test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 100000})

	local excel = excel_helper(template_path, nil, false)
	-- excel:ApplyPassportValues(mark_helper.GetExtPassport(Passport))

	excel:SaveAndShow()
	excel = nil
end

local function fff()
	local function SplitPath(path)
		local res = {}
		for p in path:gmatch('([^\\]+)') do
			table.insert(res, p)
		end
		local name = table.remove(res, #res)
		return res, name
	end
	
	local function CreatePath(path)
		local fso = luacom.CreateObject("Scripting.FileSystemObject")
		local full_path = table.remove(path, 1) .. "\\"
		for _, p in ipairs(path) do
			full_path = full_path .. p .. "\\"
			if not fso:FolderExists(full_path) then
				assert( fso:CreateFolder(full_path) )
			end
		end
		return full_path
	end

	local function CopyFile(src, dst)
		local fso = luacom.CreateObject("Scripting.FileSystemObject")
		assert(fso, "can not create FileSystemObject object")

		if not fso:FileExists(src) then
			errorf("template %s not exist", src)
		end

		local path, name = SplitPath(dst)
		path = CreatePath(path)
		assert(dst == path .. name)
		fso:CopyFile(src, dst, True)
		return fso:FileExists(dst)
	end

	local function GetFileExtension(path)
		return path:match("^.+(%..+)$")
	end

	local function CopyTemplate(template_path, sheet_name, dest_name)		-- скопировать файл шаблона в папку отчетов
		local file_name
		if dest_name then
			file_name = dest_name
		else
			file_name = os.date('%y%m%d-%H%M%S')
			if sheet_name then
				file_name = file_name .. '_' .. sheet_name
			end
		end

		local user_dir = os.getenv('USERPROFILE') -- возвращает путь кодированный в cp1251, что вызывает ошибку при копировании, тк ожидается utf-8
		--user_dir = codecs.cp1251_utf8(user_dir)
		local new_name = user_dir .. '\\ATapeReport\\' .. file_name .. GetFileExtension(template_path)
		if not CopyFile(template_path, new_name) then
			errorf('copy file %s -> %s failed', template_path, new_name)
		end
		return new_name
	end
	
	local function OpenWorkbook(workbooks, file_path)
		for i = 1, workbooks.Count do							-- поищем среди открытых или откроем его
			local wb = workbooks(i)
			if wb.FullName == file_path then
				return wb
			end
		end
		return workbooks:Open(file_path)
	end
	
	local function FindWorkSheet(workbook, sheet_name)
		local ws2del = {}										-- список листов для удаления
		local worksheet

		for i = 1, workbook.Worksheets.Count do
			local sheet = workbook.Worksheets(i)				-- ищем лист с нужным именем
			-- print(i, sheet.name)
			if not sheet_name or #sheet_name == 0 or sheet.name == sheet_name then
				worksheet = sheet								-- сохраняем для использования
				worksheet:Activate()							-- и активируем его
			elseif sheet.name ~= "STOP" then
				table.insert(ws2del, sheet)						-- остальные соберем для удаления
			end
		end

		if worksheet then
			workbook.Application.DisplayAlerts = false;			-- отключим предупреждения
			for _, ws in ipairs(ws2del) do ws:Delete() end		-- удаляем ненужные листы
			workbook.Application.DisplayAlerts = true;			-- включим предупреждения обратно
		end

		return worksheet
	end

	local excel = luacom.CreateObject("Excel.Application") 		-- запустить экземпляр excel
	assert(excel, "Error! Could not run EXCEL object!")

	-- excel.Visible = true

	local file_path = CopyTemplate(template_path, "", nil)	-- скопируем шаблон в папку отчетов
	local workbooks = excel.Workbooks
	local workbook = OpenWorkbook(workbooks, file_path)
	--assert(workbook, sprintf("can not open %s", file_path))
	workbook:Close()
	workbook = nil
	
	workbooks:Close()
	collectgarbage("collect")
	workbooks = nil
	collectgarbage("collect")
	
--	local worksheet = FindWorkSheet(workbook, sheet_name)
--	assert(worksheet, sprintf('can not find "%s" worksheet', sheet_name))

	excel:Quit()
	collectgarbage("collect")
	excel = nil
	collectgarbage("collect")
end

fff()

Sleep(5)

if not is_runned() then
	print("CLOSE!")
else
	print('still stay')
end
