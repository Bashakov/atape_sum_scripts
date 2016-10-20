if not ATAPE then
	require "iuplua" 
	socket = require 'socket'
end

-- OOP = require 'OOP'

stuff = require 'stuff'
ProgressDlg = require 'progressDlg'
excel_helper = require 'excel_helper'

-- =================================================================================


local function dump_mark_list(template_name, sheet_name)
	
	local filedlg = iup.filedlg{
		dialogtype = "SAVE", 
		title = "Select file to save mark lua testing dump", 
		filter = "*.lua", 
		filterinfo = "lua file",
        directory="c:\\",
		} 
	filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)
	if filedlg.status == -1 then
		return
	end

	local marks = Driver:GetMarks()
	local dlg = ProgressDlg()
	
	local out = {}
	for i = 1, #marks do 
		local mark = marks[i]
		out[i] = {prop = mark.prop, ext = mark.ext})
		
		if not dlg:step(1.0 * i / #marks, stuff.sprintf('progress %d / %d mark', i, #marks)) then 
			return 
		end
	end
	
	dlg:step(1, 'Dump saving ...');
	local prev_output = io.output()
	io.output(filedlg.value)
	stuff.save("marks", out)
	io.output(prev_output)
end


local function mark2excel(template_name, sheet_name)
	local marks = Driver:GetMarks()
	
	local dlg = ProgressDlg()
	
	local worksheet = excel_helper.GetWorksheet('C:\\Users\\abashak\\Desktop\\lua_test\\ProcessSum.xls', 'Ведомость Зазоров', false)
	excel_helper.ProcessPspValues(worksheet, Passport)
	local data_range = excel_helper.CopyTemplateRow(worksheet, #marks, 
		function(i) 
--			os.sleep(0.1)
			return dlg:step(1.0 * i / #marks, stuff.sprintf('insert excel row %d / %d', i, #marks))
		end)
	
	if not dlg:step(0) then
		return
	end
	
	assert(#marks == data_range.Rows.count, 'misamtch count of marks and table rows')
	
	for i = 1, #marks do 
		local mark = marks[i]
		local c = 1
		
		for n, v in pairs(mark.prop) do
			data_range.Cells(i, c).Value2 = stuff.sprintf('%s=%s', n, v)
			c = c + 1
		end
		for n, v in pairs(mark.ext) do
			data_range.Cells(i, c).Value2 = stuff.sprintf('%s=%s', n, v)
			c = c + 1
		end
		
		--excel_helper.InsertLink(data_range.Cells(i, 10), 'http://google.com', 'google')
		
		--excel_helper.InsetImage(data_range.Cells(i, 8), mark.img_path)
	
		if not dlg:step(1.0 * i / #marks, stuff.sprintf(' Process %d / %d mark', i, #marks)) then 
			return 
		end
		--os.sleep(0.1)
	end
	
	worksheet.Application.visible = true
	worksheet.Parent:Save()
	
	dlg:step(1, 'save dump');
end

-- ====================================================================================

local gap_rep_filter_guids = 
{
	"{19253263-2C0B-41EE-8EAA-000000000010}",
	"{19253263-2C0B-41EE-8EAA-000000000040}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC801}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC802}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC803}",
}

local beacon_rep_filter_guids = 
{
	"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}",
	"{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",
}



local Report_Functions = {
--	{name="Ведомость Зазоров| < 3 мм",		fn=rep_gaps_less3,		filename="ProcessSum.xls",	sheetname="Ведомость Зазоров", 			guids=gap_rep_filter_guids},
--	{name="Ведомость Зазоров| Все",			fn=rep_gaps_all,		filename="ProcessSum.xls",	sheetname="Ведомость Зазоров", 			guids=gap_rep_filter_guids},
--	{name="Ведомость Зазоров| > 22 мм",		fn=rep_gaps_gtst22,		filename="ProcessSum.xls",	sheetname="Ведомость Зазоров", 			guids=gap_rep_filter_guids},
--	{name="Ведомость сварной плети",		fn=report_welding,		filename="ProcessSum.xls",	sheetname="Ведомость сварной плети", 	guids=beacon_rep_filter_guids},
--	{name="Ведомость ненормативных объектов",fn=report_unspec_obj,	filename="ProcessSum.xls",	sheetname="Ненормативные объекты", 		guids=unspec_obj_filter_guids},
	{name="Сделать дамп отметок",			fn=dump_mark_list,		filename="ProcessSum.xls",	sheetname="test", },
	{name="Сохранить в Excel",				fn=mark2excel,			filename="ProcessSum.xls",	sheetname="test", },
}


-- ================================ EXPORT FUNCTIONS ================================= --


function GetAvailableReports() -- exported
	res = {}
	for _, n in ipairs(Report_Functions) do 
		table.insert(res, n.name)
	end
	return res
end

function MakeReport(name) -- exported
	for _, n in ipairs(Report_Functions) do 
		if n.name == name then
			if n.fn then
				name = nil
				ok, msg = pcall(n.fn, n.filename, n.sheetname)
				if not ok then 
					error(msg)
				end
			end
		end
	end
	
	if name then -- if reporn not found
		errorf('can not find report [%s]', name)
	end
end

function GetFilterGuids(reportName)
	local guids = {}
	for _, n in ipairs(Report_Functions) do 
		local item_name = n.name:sub(1, reportName:len())
		if item_name == reportName and n.guids then
			for _, g in ipairs(n.guids) do
				guids[g] = true;
			end
		end
	end
	
	local res = {}
	for k,_ in pairs(guids) do table.insert(res, k) end
	return res;
end

