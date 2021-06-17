if not ATAPE then
	require "iuplua"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local sqlite3 = require "lsqlite3"
local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local EKASUI_REPORT = require 'sum_report_ekasui'
local AVIS_REPORT = require 'sum_report_avis'
local sumPOV = require "sumPOV"
local OOP = require 'OOP'

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf

local GUID_BEACON 					= "{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"	-- Маячная
local GUID_BEACON_SPALA 			= "{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}" 	-- Маячная(Пользователь)
local GUID_USER_JOINTLESS_DEFECT 	= "{3601038C-A561-46BB-8B0F-F896C2130006}"	-- Бесстыковой путь(Пользователь)
local GUID_BEACON_FIRTREE 			= "{D3736670-0C32-46F8-9AAF-3816DE00B755}"	-- Маячная Ёлка

local juids_beacon =
{
	GUID_BEACON,
	GUID_BEACON_SPALA,
	GUID_USER_JOINTLESS_DEFECT,
	GUID_BEACON_FIRTREE,
}


local function GetMarks(ekasui, pov_filter, dlgProgress)
	if not pov_filter then
		pov_filter = sumPOV.MakeReportFilter(ekasui)
	end
	if not pov_filter then return {} end
	local marks = Driver:GetMarks{GUIDS=juids_beacon}
	marks = pov_filter(marks, dlgProgress)
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

local function MakeBeaconMarkRow(mark)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	row.BEACON_OFFSET = ''
	row.OUT_PARAM = ''
	return row
end

-- =========================================================================

local function generate_row_beacon(marks, dlgProgress)

	local ok, max_offset = true, 10
	ok, max_offset  = iup.GetParam("Отчет по маячным отметкам", nil, "Смещение: %i\n", max_offset)
	if not ok then
		return
	end

	local report_rows = {}
	for i, mark in ipairs(marks) do
		if mark.prop.Guid == GUID_USER_JOINTLESS_DEFECT and mark.ext.CODE_EKASUI == DEFECT_CODES.BEACON_UBNORMAL_MOVED[1] then
			local row = MakeBeaconMarkRow(mark)
			row.DEFECT_CODE = mark.ext.CODE_EKASUI
			row.DEFECT_DESC = DEFECT_CODES.code2desc(mark.ext.CODE_EKASUI) or string.match(mark.prop.Description, '([^\n]+)\n')
			table.insert(report_rows, row)
		else
			local offset = mark_helper.GetBeaconOffset(mark)

			if offset and math.abs(offset) > max_offset then
				local row = MakeBeaconMarkRow(mark)
				row.BEACON_OFFSET = offset
				row.OUT_PARAM = offset
				row.DEFECT_CODE = DEFECT_CODES.BEACON_UBNORMAL_MOVED[1]
				row.DEFECT_DESC = DEFECT_CODES.BEACON_UBNORMAL_MOVED[2]
				table.insert(report_rows, row)
			end
		end

		if i % 300 == 0 then collectgarbage("collect") end
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local function generate_row_beacon_user(marks, dlgProgress)
	local report_rows = {}
	for i, mark in ipairs(marks) do
		if mark.prop.Guid == GUID_USER_JOINTLESS_DEFECT and mark.ext.CODE_EKASUI then
			local row = MakeBeaconMarkRow(mark)
			row.DEFECT_CODE = mark.ext.CODE_EKASUI
			row.DEFECT_DESC = DEFECT_CODES.code2desc(mark.ext.CODE_EKASUI) or string.match(mark.prop.Description, '([^\n]+)\n')
			table.insert(report_rows, row)
		end

		if i % 300 == 0 then collectgarbage("collect") end
		if i % 50 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d (user)', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

local SearchMissingBeacons = OOP.class
{
	ctor = function (self)
		self.beacons = {{}, {}}
	end,

	add_beacons = function (self, sys, rail)
		for r, marks in ipairs(self.beacons) do
			if bit32.btest(rail, r) then
				table.insert(marks, sys)
			end
		end
	end,

	prepare = function (self)
		for _, marks in ipairs(self.beacons) do
			table.sort(marks)
		end
	end,

	get_beacon = function (self, sys, rail, dist)
		for r, marks in ipairs(self.beacons) do
			if bit32.btest(rail, r) then
				local i1 = mark_helper.lower_bound(marks, sys-dist)
				local i2 = mark_helper.lower_bound(marks, sys+dist)
				if i1 ~= i2 then
					return true
				end
			end
		end
		return false
	end
}

local function generate_missing_beacon_mark(marks, dlgProgress)
	-- local beacons = {} -- список маячных отметок с рисками по рельсам
	local searcher = SearchMissingBeacons()
	local report_rows = {}

	local beacons = 0
	for i, mark in ipairs(marks) do
		if mark.prop.Guid == GUID_BEACON_SPALA or
		   mark.prop.Guid == GUID_BEACON then
			local rail_mask = bit32.band(mark.prop.RailMask, 0x03)
			searcher:add_beacons(mark.prop.SysCoord, rail_mask)
			beacons = beacons+1
		end

		if i % 300 == 0 then collectgarbage("collect") end
		if i % 34 == 0 and not dlgProgress:step(i / #marks, sprintf('поиск маячных отметок %d / %d, найдено %d', i, #marks, beacons)) then
			return
		end
	end

	searcher:prepare()

	-- проходим по всем елкам и ищем для них соответствующие отметка с рисками
	local MAX_DISTANCE_TO_BEACON_TO_MISS = 300 -- интервал в котором относительно елки ищется маячная метка
	for i, mark in ipairs(marks) do
		if mark.prop.Guid == GUID_BEACON_FIRTREE then
			local rail_mask = bit32.band(mark.prop.RailMask, 0x03)
			local found = searcher:get_beacon(mark.prop.SysCoord, rail_mask, MAX_DISTANCE_TO_BEACON_TO_MISS)
			if not found then
				local row = MakeBeaconMarkRow(mark)
				row.DEFECT_CODE = DEFECT_CODES.BEACON_MISSING_LINE[1]
				row.DEFECT_DESC = DEFECT_CODES.code2desc(row.DEFECT_CODE)
				table.insert(report_rows, row)
			end
		end

		if i % 300 == 0 then collectgarbage("collect") end
		if i % 34 == 0 and not dlgProgress:step(i / #marks, sprintf('Поиск %d / %d отметок, дефектов %d', i, #marks, #report_rows)) then
			return
		end
	end
	return report_rows
end

local function report_not_implement()
	iup.Message('Error', "Отчет не реализован")
end

-- =========================================================================

local function make_report_generator(...)

	local report_template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ БЕССТЫКОВОГО ПУТИ.xlsm'
	local sheet_name = 'В6 БП'

	return AVIS_REPORT.make_report_generator(function() return GetMarks(false) end,
		report_template_name, sheet_name, ...)
end

local function make_report_ekasui(...)
	return EKASUI_REPORT.make_ekasui_generator(function(dlgProgress) return GetMarks(true, nil, dlgProgress) end, ...)
end

local function make_report_videogram(...)
	local row_generators = {...}

	local function gen(mark)
		local report_rows = {}
		if mark and mark_helper.table_find(juids_beacon, mark.prop.Guid) then
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

local report_beacon = make_report_generator(generate_row_beacon)
local ekasui_beacon = make_report_ekasui(generate_row_beacon)
local report_missing_beacon_mark = make_report_generator(generate_missing_beacon_mark)
local ekasui_missing_beacon_mark = make_report_ekasui(generate_missing_beacon_mark)

local videogram = make_report_videogram(generate_row_beacon)

local report_beacon_all = make_report_generator(generate_row_beacon_user, generate_row_beacon, generate_missing_beacon_mark)
local ekasui_beacon_all = make_report_ekasui(generate_row_beacon_user, generate_row_beacon, generate_missing_beacon_mark)


-- =========================================================================

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании бесстыкового пути|'

	local sleppers_reports =
	{
		{name = name_pref..'Все',    				fn=report_beacon_all, },
		{name = name_pref..'ЕКАСУИ Все',    		fn=ekasui_beacon_all, },

		{name = name_pref..'Смещения рельсовых плетей относительно «маячных» шпал, мм',    		fn=report_beacon, 			},
		{name = name_pref..'ЕКАСУИ Смещения рельсовых плетей относительно «маячных» шпал, мм',  fn=ekasui_beacon, 			},
		{name = name_pref..'Отсутствует маркировка «маячных» шпал', 							fn=report_missing_beacon_mark},
		{name = name_pref..'ЕКАСУИ Отсутствует маркировка «маячных» шпал', 						fn=ekasui_missing_beacon_mark},
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=juids_beacon
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then
	local test_report  = require('test_report')
	--test_report('D:\\ATapeXP\\Main\\494\\Москва Курская - Подольск\\Москва Курская - Подольск\\2019_05_16\\Avikon-03M\\4240\\[494]_2019_03_15_01.xml')
	--test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	--test_report('D:/d-drive/ATapeXP/Main/494/video_recog/2020_08_24/Avikon-03M/4858/[494]_2019_09_03_01.xml')
	test_report('D:\\Downloads\\722\\2021.03.23\\[492]_2021_01_26_02.xml', nil, {0, 1000000000})

	-- report_beacon_user()
	generate_row_beacon_user()
	-- report_beacon()
	--ekasui_beacon()
	-- ekasui_missing_beacon_mark()
end

return {
	AppendReports = AppendReports,
	videogram = videogram,
	all_generators = {
		{generate_row_beacon_user, 		"Установленые пользователем"},
		{generate_row_beacon, 			"Смещения рельсовых плетей относительно «маячных» шпал"},
		{generate_missing_beacon_mark, 	"Отсутствует маркировка «маячных» шпал"},
	},
	get_marks = function (pov_filter)
		return GetMarks(false, pov_filter)
	end,
}
