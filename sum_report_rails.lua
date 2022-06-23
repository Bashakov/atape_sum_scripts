if false then iup = nil; luacom = nil; ATAPE = nil; Driver = nil end -- suppress lua diagnostic (undefined global)

if not ATAPE then
	require "iuplua"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local EKASUI_REPORT = require 'sum_report_ekasui'
local AVIS_REPORT = require 'sum_report_avis'
local sumPOV = require "sumPOV"
local TYPES = require 'sum_types'

local table_find = mark_helper.table_find

-- ==================================================================

local guid_surface_defects =
{
	TYPES.VID_SURF,	-- Поверх.(Видео)
}

local guid_surface_user =
{
	"{3601038C-A561-46BB-8B0F-F896C2130004}", 	-- Дефекты рельсов(Пользователь)
}

local filter_juids = mark_helper.table_merge(guid_surface_defects, guid_surface_user)


local function get_user_filter_surface()
		local res, user_width, user_lenght, user_area = iup.GetParam(
			"Фильтрация ( AND ) дефектов", nil,
			"Ширина(поперек рельса), мм  >=: %s\n\z
			Длина(вдоль рельса), мм >=: %s\n\z
			Площадь(д.б. число), см**2 >=: %i\n",
			'', '', 10)

	if not res then
		return
	end

	user_width = #user_width > 0 and tonumber(user_width)
	user_lenght = #user_lenght > 0 and tonumber(user_lenght)
	return user_area, user_width, user_lenght
end


local function GetMarks(ekasui, pov_filter)
	if not pov_filter then
		pov_filter = sumPOV.MakeReportFilter(ekasui)
	end
	if not pov_filter then return {} end
	local marks = Driver:GetMarks{GUIDS=filter_juids}
	marks = pov_filter(marks)
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

-- =============================================================================


local function generate_rows_rails(marks, dlgProgress)
	if #marks == 0 then return end
	local user_area, user_width, user_lenght = get_user_filter_surface()
	if not user_area then
		return
	end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if table_find(guid_surface_defects, mark.prop.Guid) and mark.ext.RAWXMLDATA then
			local surf_prm = mark_helper.GetSurfDefectPrm(mark)
			if surf_prm then

				-- https://bt.abisoft.spb.ru/view.php?id=251#c592
				local mark_length = surf_prm.SurfaceLength
				local mark_width = surf_prm.SurfaceWidth
				local mark_area = surf_prm.SurfaceArea

				local accept = true
					accept =
						(not user_width or (mark_width and mark_width >= user_width)) and
						(not user_lenght or (mark_length and mark_length >= user_lenght)) and
						(mark_area >= user_area)

				print(user_width, user_lenght, user_area, '|', mark_width, mark_length,  mark_area,  '=', accept)

				if accept then
					local row = mark_helper.MakeCommonMarkTemplate(mark)
					row.DEFECT_CODE = DEFECT_CODES.RAIL_SURF_DEFECT[1]
					row.DEFECT_DESC = DEFECT_CODES.RAIL_SURF_DEFECT[2]
					table.insert(report_rows, row)
				end
			end
		end

		if table_find(guid_surface_user, mark.prop.Guid) and mark.ext.CODE_EKASUI == DEFECT_CODES.RAIL_SURF_DEFECT[1] then
			local row = mark_helper.MakeCommonMarkTemplate(mark)
			row.DEFECT_CODE = mark.ext.CODE_EKASUI
			row.DEFECT_DESC = DEFECT_CODES.code2desc(mark.ext.CODE_EKASUI)
			table.insert(report_rows, row)
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function generate_rows_rails_user(marks, dlgProgress)
	if #marks == 0 then return end

	local report_rows = {}
	for i, mark in ipairs(marks) do

		if table_find(guid_surface_user, mark.prop.Guid) and mark.ext.CODE_EKASUI then
			local row = mark_helper.MakeCommonMarkTemplate(mark)
			row.DEFECT_CODE = mark.ext.CODE_EKASUI
			row.DEFECT_DESC = DEFECT_CODES.code2desc(mark.ext.CODE_EKASUI)
			table.insert(report_rows, row)
		end

		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

-- =============================================================================


local function make_report_generator(...)
	local report_template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ РЕЛЬСОВ.xlsm'
	local sheet_name = 'В4 РЛС'
	return AVIS_REPORT.make_report_generator(function() return GetMarks(false) end,
		report_template_name, sheet_name, ...)
end

local function make_report_ekasui(...)
	return EKASUI_REPORT.make_ekasui_generator(function() return GetMarks(true) end, ...)
end

local function make_report_videogram(...)
	local row_generators = {...}

	local function gen(mark)
		local report_rows = {}
		if mark and mark_helper.table_find(filter_juids, mark.prop.Guid) then
			for _, fn_gen in ipairs(row_generators) do
				local cur_rows = fn_gen({mark}, nil)
				for _, row in ipairs(cur_rows) do
					table.insert(report_rows, row)
				end
			end
		end
		return report_rows
	end

	return gen
end

-- =============================================================================

local report_rails = make_report_generator(generate_rows_rails)
local ekasui_rails = make_report_ekasui(generate_rows_rails)
local videogram = make_report_videogram(generate_rows_rails)

local report_rails_all = make_report_generator(generate_rows_rails_user, generate_rows_rails)
local ekasui_rails_all = make_report_ekasui(generate_rows_rails_user, generate_rows_rails)

-- =============================================================================



local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании рельсов|'
	local name_surf = 'Определение и вычисление размеров поверхностных дефектов рельсов, седловин, в том числе в местах сварки, пробуксовок (длина, ширина и площадь)'

	local sleppers_reports =
	{
		{name = name_pref .. name_surf,    					fn = report_rails},
		{name = name_pref .. 'ЕКАСУИ ' .. name_surf,   		fn = ekasui_rails},

		{name = name_pref .. 'Все',    						fn = report_rails_all},
		{name = name_pref .. 'ЕКАСУИ Все',   				fn = ekasui_rails_all},
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids = filter_juids
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then

	local test_report  = require('test_report')
	test_report('D:\\ATapeXP\\Main\\494\\video\\[494]_2017_06_08_12.xml')

	local reports = {};
	AppendReports(reports)

	local report = reports[4]
	print('name: ', report.name)
	print('GUIDS:' , table.concat(report.guids, ', '))
	report.fn()
	--ekasui_rails()
end

return {
	AppendReports = AppendReports,
	videogram = videogram,
	all_generators = {
		{generate_rows_rails_user,	"Установленые пользователем"},
		{generate_rows_rails,		"поверхностных дефектов рельсов"},
	},
	get_marks = function (pov_filter)
		return GetMarks(false, pov_filter)
	end,
}
