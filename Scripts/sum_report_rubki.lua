local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
require "ExitScope"
local resty = require "resty.template"
local OOP = require 'OOP'
local EKASUI = require "sum_report_ekasui"
local TYPES = require 'sum_types'
local utils = require 'utils'
local xml_utils = require 'xml_utils'

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

local printf  = utils.printf
local sprintf = utils.sprintf


-- =============================================== --

local joints_guids =
{
	TYPES.VID_INDT_1,
	TYPES.VID_INDT_2,
	TYPES.VID_INDT_3,
	TYPES.VID_INDT_ATS,
	TYPES.VID_ISO, 	-- ИзоСтык(Видео)
}

local switch_guids = {
	"{19253263-2C0B-41EE-8EAA-000000100000}",
	"{19253263-2C0B-41EE-8EAA-000000200000}",
	"{19253263-2C0B-41EE-8EAA-000000400000}",
	"{19253263-2C0B-41EE-8EAA-000000800000}",
}

local sleeper_guids = {
	"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}",
}

local fastener_guids = {
	TYPES.FASTENER,
}

local SLEEPER_DIST_REF = 1000000 / 1840

-- =============================================== --

-- вычислить длину рельса между двумя стыками с учетом ширины зазора
local function get_rail_len(mark1, mark2)
	local l = math.abs(mark2.prop.SysCoord - mark1.prop.SysCoord)
	local w1 = mark_helper.GetGapWidth(mark1) or 0
	local w2 = mark_helper.GetGapWidth(mark2) or 0
	return l - (w1 + w2) / 2
end

--[[ проверить что отметки рельс является рубкой

2020.06.18 ТребованияРУБКИ.docx:
к рельсовым рубкам относятся рельсы, длина которых отличается от стандартной (25,0-24,84 м, 12,52 – 12,38 м)
и находится в диапазоне от 6 до 25 метров ]]
local function check_rail_is_rubka(mark1, mark2)
	local rail_len = get_rail_len(mark1, mark2) / 1000.0
	if rail_len < 25 and rail_len > 24.84 then
		return false
	end
	if rail_len < 12.52 and rail_len > 12.38 then
		return false
	end
	return true
end

-- ищет рубки, возвращает массив пар отметок, ограничивающих врезку
local function scan_for_short_rail(marks, min_length, show_only_rubki)
	if not marks then return nil end

	local res = {}
	local prev_mark = {}

	for _, mark in ipairs(marks) do
		local rail = bit32.band(mark.prop.RailMask)
		local coord = mark.prop.SysCoord
		if prev_mark[rail] and
		   (not min_length or coord - prev_mark[rail].coord < min_length) and
		   (not show_only_rubki or check_rail_is_rubka(prev_mark[rail].mark, mark))
		then
			table.insert(res, {prev_mark[rail].mark, mark})
		end
		prev_mark[rail] = {coord=coord, mark=mark}
	end
	return res
end

-- проверить что координата находится в стрелке
local function is_inside_switch(switches, coords)
	for _, switch in ipairs(switches) do
		local inside = true
		for _, c in ipairs(coords) do
			if c < switch.from or switch.to < c then
				inside = false
				break
			end
		end
		if inside then
			return switch.id
		end
	end
	return nil
end

-- найти все стрелки
local function scan_for_rr_switch()
	local marks = Driver:GetMarks{ListType='all', GUIDS=switch_guids}
	local res = {}
	for i = 1, #marks do
		local mark = marks[i]
		local prop = mark.prop
		res[#res+1] = {from=prop.SysCoord, to=prop.SysCoord + prop.Len, id=prop.ID}
	end
	printf('found %d switches', #res)
	return res
end

-- сгенерировать и вставить картинку в отчет
local function insert_frame(excel, data_range, mark, row, col, video_channel, show_range)
	local img_path
	local ok, msg = pcall(function ()
			img_path = mark_helper.MakeMarkImage(mark, video_channel, show_range, false)
		end)
	if not ok then
		data_range.Cells(row, col).Value2 = msg and #msg and msg or 'Error'
	elseif img_path and #img_path then
		excel:InsertImage(data_range.Cells(row, col), img_path)
	end
end

local function make_rail_image(mark1, mark2)
	local ok, img_data = pcall(function ()
			return mark_helper.MakeMarkImage(mark1, nil, {mark1.prop.SysCoord-500, mark2.prop.SysCoord+500}, true)
		end)
	return ok, img_data
end

-- запрос у пользователя верхнего порога длинны рельса
--!!! закомментирована часть диалога, которая не работает при формировании выходной формы, верхний порог по умолчанию установлен 300000.
--!!! В настоящее время параметр может быть задан статически - интерактивный ввод/подтверждение избыточны.
-- https://bt.abisoft.spb.ru/view.php?id=999
local function askUpperRailLen()
	return 300000, false
	-- return min_length, show_only_rubki
end

-- получить список с отметками стыков, отсортированный по системной координате
local function get_marks(dlg)
	local marks = Driver:GetMarks({GUIDS=joints_guids})
	marks = mark_helper.filter_marks(marks,
		function (mark) -- filter
			return mark.ext.RAWXMLDATA
		end,
		function (all, checked, accepted) -- progress
			if checked % 50 == 0 and dlg then
				dlg:step(checked / all, string.format('Сканирование %d / %d отметок, выбрано %d', checked, all, accepted))
			end
		end
	)
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

local function add_text_node(parent, name, text)
	local node = parent.ownerDocument:createElement(name)
	parent:appendChild(node)
	node.text = text or ''
	return node
end

local function add_node(parent, name, attrib)
	local dom = parent.ownerDocument or parent
	local node = dom:createElement(name)
	parent:appendChild(node)
	for n, v in pairs(attrib or {}) do
		node:setAttribute(n, v)
	end
	return node
end

local function get_left(mark)
	local pos = mark_helper.GetMarkRailPos(mark) -- возвращает: -1 = левый, 0 = оба, 1 = правый
	-- return pos < 0 and 1 or 0
	return pos > 0 and 1 or 0  -- 0 левая 1 правая требование окт 2020
end

local function load_near_marks(join_mark, mark_types, mark_count, search_dist)
	local filter = {
		GUIDS = mark_types,
		FromSys = join_mark.prop.SysCoord - search_dist,
		ToSys = join_mark.prop.SysCoord + search_dist,
		ListType = 'all',
	}
	local marks = Driver:GetMarks(filter)
	marks = mark_helper.sort_mark_by_coord(marks)

	-- найдем по mark_count ближайшие отметки с каждой стороны
	local left = {}
	for i = #marks, 1, -1 do
		local mark = marks[i]
		if mark.prop.SysCoord <= join_mark.prop.SysCoord and #left < mark_count then
			table.insert(left, 1, mark)
		end
	end

	local right = {}
	for i = 1, #marks, 1 do
		local mark = marks[i]
		if mark.prop.SysCoord >= join_mark.prop.SysCoord and #right < mark_count then
			table.insert(right, mark)
		end
	end

	-- объединим 2 списка
	for _, m in ipairs(right) do
		table.insert(left, m)
	end
	return left
end

local CHECK_SLEEPER_COUNT = 3
local SEARCH_DIST = CHECK_SLEEPER_COUNT * SLEEPER_DIST_REF * 1.5 -- возьмем с запасом

local function get_sleepers_params(join_mark)
	-- https://bt.abisoft.spb.ru/view.php?id=638
	-- 2. относительно зазора отсчитываются 3 шпалы влево и вправо и для них заполняются epur и skrepl

	-- проверим эпюру и дефекты шпал
	local epur_errors = 0

	local sleepers = load_near_marks(join_mark, sleeper_guids, CHECK_SLEEPER_COUNT, SEARCH_DIST)
	for i = 1, #sleepers-1 do
		local l = sleepers[i]
		local r = sleepers[i+1]
		local dist = r.prop.SysCoord - l.prop.SysCoord
		local dist_error = math.abs(dist - SLEEPER_DIST_REF)
		if dist_error > 80 then
			epur_errors = epur_errors + 1
		end
	end

	-- дефекты шпал
	local sleeper_defects = 0
	for _, mark in ipairs(sleepers) do
		local params = mark_helper.GetSleeperFault(mark)
		if params and params.FaultType and params.FaultType > 0 then
			sleeper_defects = sleeper_defects + 1
		end
	end

	-- тип шпал
	local sleeper_material
	for _, mark in ipairs(sleepers) do
		sleeper_material = mark_helper.GetSleeperMeterial(mark)
		if sleeper_material then
			break
		end
	end

	-- https://bt.abisoft.spb.ru/view.php?id=813#c4122 0 - нормальная эпюра на 6 шпалах, 1 - хотя бы одно нарушение эпюры
	local epur = 0
	if epur_errors ~= 0 then
		epur = 1
	end

	return epur, sleeper_defects, sleeper_material
end

local function get_skrepl_params(join_mark)
	-- проверим скрепления
	--[[
		https://bt.abisoft.spb.ru/view.php?id=785
		diffelasticity 15. Разноупругость основания
		Логическое
			1 - Одинаковые шпалы (ДШ или ЖБШ)
			0 - Шпалы различаются (ДШ или ЖБШ)
		Тип шпал определяем по скреплениям:
		АРС, ЖБР, Пандрол, КБ – ЖБШ
		ДО, КД - ДШ
		Все это в зоне стыка +/- 3 стыка
	]]
	local skrepl_defect_cnt = 0
	local fasteners = load_near_marks(join_mark, fastener_guids, CHECK_SLEEPER_COUNT, SEARCH_DIST)

	local fastener_type2sleeper_type = {
		[0] = 1, -- ЖБШ КБ-65
		[1] = 1, -- ЖБШ Аpc'
		[2] = 2, -- ДШ  ДО скрепление на деревянной шпале на костылях
		[3] = 2, -- ДШ  КД скрепление на деревянной шпале как КБ-65 но на двух шурупах
	}

	local sleeper_types = {}
	for i = 1, #fasteners do
		local f = fasteners[i]
		local prm = mark_helper.GetFastenetParams(f)
		if prm and prm.FastenerFault and prm.FastenerFault > 0 then
			skrepl_defect_cnt = skrepl_defect_cnt + 1
		end

		local fastener_type = prm['FastenerType']
		local sleeper_type = fastener_type2sleeper_type[fastener_type]
		if sleeper_type then
			sleeper_types[sleeper_type] = true
		end
	end
	skrepl_defect_cnt = math.min(skrepl_defect_cnt, 12)
	local diffelasticity = sleeper_types[1] and sleeper_types[2] -- если присутствуют оба типа, то true
	return skrepl_defect_cnt, diffelasticity
end

local function get_nakl(mark)
	--[[ https://bt.abisoft.spb.ru/view.php?id=722#c3396
		2. в рубках по болтам Nakl – 0 это недопустимое значение: если нет реального значения (например излом), то не создавать

		Все накладки целые – не создавать ноду
		1 У одной накладки есть трещина или надрыв
		2 У двух накладок есть трещина или надрыв
		3 Хотя бы у одной накладки есть излом
		]]
	local fp_status, fp_broken_cnt = mark_helper.GetFishplateState(mark)
	if fp_status == 4 then
		return 3
	end
	if fp_broken_cnt >= 2 then
		return 2
	end
	if fp_broken_cnt == 1 then
		return 1
	end
end


local function get_bolt_nakltype(mark)
	local valid_on_half, broken_on_half, all_count = mark_helper.CalcValidCrewJointOnHalf(mark)

	--[[
	1 Наличие всех болтов
	2 Отсутствие 1 болта (1 нормальный) на конце рельса при 4-х дырных накладках
	3 Отсутствие 2-х болтов (1 нормальный) на конце рельса при 6 дырных накладках
	4 6 – дырные накладки: Отсутствие 3-х болтов (0 нормальных) на конце рельса
	5 4 –х дырные накладки: Отсутствие 2-х болтов (0 нормальных) на конце рельса
	]]

	local bolt
	if all_count == 6 then
		if broken_on_half == 0 then	bolt = 1 end
		if broken_on_half == 2 then	bolt = 3 end
		if broken_on_half == 3 then	bolt = 4 end
	end

	if all_count == 4 then
		if broken_on_half == 0 then	bolt = 1 end
		if broken_on_half == 1 then	bolt = 2 end
		if broken_on_half == 2 then	bolt = 5 end
	end

	local nakltype = { -- Тип накладки
		[6] = 1, -- 1 – шестидырная
		[4] = 2, -- 2 – четырехдырная
	}
	return bolt, nakltype[all_count]
end


--[[ построить изображение стыка для рубок (вид с боковых камер обоих рельсов)
	https://bt.abisoft.spb.ru/view.php?id=752#c3727]]
local function make_joint_image(mark)
	return EnterScope(function (defer)
		if ShowVideo ~= 1 then -- https://bt.abisoft.spb.ru/view.php?id=809
			return ''
		end
		local center = mark.prop.SysCoord + mark.prop.Len / 2
		local rail = bit32.band(mark.prop.RailMask, 0x03)

		local img_prop = {
			mark_id = mark.prop.ID,
			width = 900,
			height = 600,
			base64 = true,
			show_marks = 0,
		}

		local _, img_data = pcall(function ()
			return Driver:GetVideoComponentImage("КОС", center, rail, img_prop)
		end)
		return img_data
	end)
end

local function make_gap_description(mark)
	local center = mark.prop.SysCoord + mark.prop.Len / 2
	local km, m, mm = Driver:GetPathCoord(center)
	local gap_step = mark_helper.GetRailGapStep(mark)
	local epur, sleeper_defects, sleeper_material = get_sleepers_params(mark)
	local skrepl_defect_count, diffelasticity = get_skrepl_params(mark)

	local values =
	{
		epur = epur,
		skrepl = skrepl_defect_count,
		sneg = 0, -- Нода есть всегда. 0, если не определяется
		diffelasticity = diffelasticity and 1 or 0, -- 2021.05.24 ТребованияРУБКИ.docx 2. Исключение из п.1 для параметров, имеющих логический тип данных:
	}

	values.shpal_material = sleeper_material
	values.shpal = sleeper_defects
	values.bolt, values.nakltype = get_bolt_nakltype(mark)
	values.gaptype = mark_helper.GetGapType(mark)
	values.temp = mark_helper.GetTemperature(mark)
	values.left = get_left(mark)
	values.km = km
	values.m = string.format('%.3f', m + mm/1000)
	values.zazor = mark_helper.GetGapWidth(mark)
	values.gstup = gap_step and math.abs(gap_step)
	values.nakl	= get_nakl(mark)

	local img_data = make_joint_image(mark)
	return {
		values = values,
		img_data = img_data,
	}
end

-- ======================= отчеты =========================

-- отчет по коротким стыкам
local function report_short_rails_excel(params)
	EnterScope(function(defer)
		local min_length, show_only_rubki = askUpperRailLen()
		if not min_length then return end

		local dlg = luaiup_helper.ProgressDlg()
		defer(dlg.Destroy, dlg)

		local marks = get_marks(dlg)
		local short_rails = scan_for_short_rail(marks, min_length*1000, show_only_rubki)
		local rr_switchs = scan_for_rr_switch()

		local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
		excel:ApplyPassportValues(Passport)
		local data_range = excel:CloneTemplateRow(#short_rails)

		assert(#short_rails == 0 or #short_rails == data_range.Rows.count, 'misamtch count of mark and table rows')

		for line, mark_pair in ipairs(short_rails) do
			local mark1, mark2 = table.unpack(mark_pair)
			local prop1, prop2 = mark1.prop, mark2.prop
			local km1, m1, mm1 = Driver:GetPathCoord(prop1.SysCoord)
			local km2, m2, mm2 = Driver:GetPathCoord(prop2.SysCoord)
			local switch_id = is_inside_switch(rr_switchs, {prop1.SysCoord, prop2.SysCoord})

			local uri = mark_helper.MakeMarkUri(prop1.ID)
			local text_pos = sprintf("%d km %.1f = %d km %.1f", km1, m1 + mm1/1000, km2, m2 + mm2/1000)
			excel:InsertLink(data_range.Cells(line, 1), uri, text_pos)
			--data_range.Cells(line, 2).Value2 = sprintf("%.1f", (prop2.SysCoord - prop1.SysCoord) / 1000)
			data_range.Cells(line, 2).Value2 = sprintf("%.3f", get_rail_len(mark1, mark2) / 1000)
			data_range.Cells(line, 3).Value2 = mark_helper.GetRailName(mark1)
			if switch_id then
				local switch_uri = mark_helper.MakeMarkUri(switch_id)
				excel:InsertLink(data_range.Cells(line, 4), switch_uri, "Да")
			end

			local temperature = Driver:GetTemperature(bit32.band(prop1.RailMask, 3)-1, (prop1.SysCoord+prop2.SysCoord)/2 )
			local temperature_msg = temperature and temperature.target and sprintf("%.1f", temperature.target) or '-'
			data_range.Cells(line, 5).Value2 = temperature_msg:gsub('%.', ',')

			if math.abs(prop1.SysCoord - prop2.SysCoord) < 30000 then
				insert_frame(excel, data_range, mark1, line, 6, nil, {prop1.SysCoord-500, prop2.SysCoord+500})
			end

			if not dlg:step(line / #short_rails, sprintf('Сохранение %d / %d', line, #short_rails)) then
				break
			end
		end

		if ShowVideo == 0 then
			excel:AutoFitDataRows()
			data_range.Cells(5).ColumnWidth = 0
		end

		excel:SaveAndShow()
	end)
end

local GAP_PARAM_ORDER = {
	"gaptype",
	"nakltype",
	"temp",
	"left",
	"speedlimit",
	"km",
	"m",
	"pros",
	"zazor",
	"vstup",
	"gstup",
	"smatie",
	"nakl",
	"bolt",
	"viplesk",
	"skrepl",
	 "podkl",
	 "shpal",
	"epur",
	"ballast",
	"sneg",
	"diffelasticity"
}

local SaverEkasui = OOP.class
{
	ctor = function (self, proezd_params)
		self.dom = luacom.CreateObject('Msxml2.DOMDocument.6.0')
		assert(self.dom)

		self.node_videocontrol = add_node(self.dom, 'videocontrol')
		local node_proezd = add_node(self.node_videocontrol, 'proezd', {
			road=proezd_params.road,
			vagon=proezd_params.vagon,
			proezd=proezd_params.proezd,
			proverka=proezd_params.proverka
		})
		local node_way = add_node(node_proezd, 'way', {assetnum=proezd_params.assetnum})
		self.node_relset = add_node(node_way, 'relset')
		self.node_railgapset = add_node(node_way, 'railgapset')
		self.saved_gaps = {}
		self.total_size = 0
		self._min_km = nil
		self._max_km = nil
		self._min_id = nil
		self._max_id = nil
	end,

	write = function (self)
		-- local fromKM = Passport.FromKm or string.match(Passport.START_CHOORD, '^(-?%d+):') or ''
		-- local toKM = Passport.ToKm or string.match(Passport.END_CHOORD, '^(-?%d+):') or ''
		local path_dst = sprintf("%s\\%s_%03d_%03d_%06d_%06d.xml",
			EKASUI_PARAMS.ExportFolder, Passport.SOURCE,
			self._min_km, self._max_km, self._min_id, self._max_id)
		if TEST_EKASUI_OUT_PREFIX then
			path_dst = TEST_EKASUI_OUT_PREFIX .. "_1.xml"
		end
		if true then
			-- with formation
			local f = io.open(path_dst, 'w+b')
			f:write(xml_utils.msxml_node_to_string(self.dom))
			f:close()
		elseif true then
			-- no format (one line)
			self.dom:save(path_dst)
		else
			local f = io.open(path_dst, 'w+b')
			f:write('<?xml version="1.0" >')
			f:write(self.node_videocontrol.xml)
			f:close()
		end
		return path_dst
	end,

	add_rail = function(self, i, mark_pair)
		self:_rail2xml(i, mark_pair)
		for _, mark in ipairs(mark_pair) do
			self:_gap2xml(mark)
		end
	end,

	_update_km_range = function(self, km)
		self._min_km = self._min_km and math.min(self._min_km, km) or km
		self._max_km = self._max_km and math.max(self._max_km, km) or km
	end,

	_update_id_range = function(self, id)
		self._min_id = self._min_id and math.min(self._min_id, id) or id
		self._max_id = self._max_id and math.max(self._max_id, id) or id
	end,

	_rail2xml = function (self, i, mark_pair)
		local mark1, mark2 = table.unpack(mark_pair)
		local km1, m1, mm1 = Driver:GetPathCoord(mark1.prop.SysCoord)
		local km2, m2, mm2 = Driver:GetPathCoord(mark2.prop.SysCoord)
		self:_update_km_range(km1)
		self:_update_km_range(km2)
		self:_update_id_range(mark1.prop.ID)
		self:_update_id_range(mark2.prop.ID)

		local node_rels = add_node(self.node_relset, 'rels', {relsid=i})
		add_text_node(node_rels, 'bgapid', mark1.prop.ID)
		add_text_node(node_rels, 'egapid', mark2.prop.ID)
		add_text_node(node_rels, 'left', get_left(mark1))
		add_text_node(node_rels, 'bkm', km1)
		add_text_node(node_rels, 'bm', string.format('%.3f', m1 + mm1/1000))
		add_text_node(node_rels, 'ekm', km2)
		add_text_node(node_rels, 'em', string.format('%.3f', m2 + mm2/1000))
		add_text_node(node_rels, 'length', string.format('%.3f', (mark2.prop.SysCoord - mark1.prop.SysCoord)/1000))
		self.total_size = self.total_size + 250 -- примерный размер xml описания
	end,

	_gap2xml = function (self, mark)
		if self.saved_gaps[mark.prop.ID] then
			return
		end
		self.saved_gaps[mark.prop.ID] = true

		local gap_params = make_gap_description(mark)

		local node_railgap = add_node(self.node_railgapset, 'railgap', {
			gapid=mark.prop.ID,
			avikon_system_coord=mark.prop.SysCoord})
		for _, param_name in ipairs(GAP_PARAM_ORDER) do
			if gap_params.values[param_name] then
				add_text_node(node_railgap, param_name, gap_params.values[param_name])
			end
		end

		local node_picset = add_node(node_railgap, 'picset')
		add_text_node(node_picset, 'pic', gap_params.img_data)
		if gap_params.img_error then
			add_text_node(node_picset, 'error', gap_params.img_error)
		end
		self.total_size = self.total_size + 370 -- примерный размер xml описания
		self.total_size = self.total_size + #gap_params.img_data
	end
}

local function save_short_rails_ekasui(proezd_params, dlg, short_rails)
	local MAX_SIZE = 20 * 1024 * 1024
	local files = {}
	local saver = SaverEkasui(proezd_params)

	for i, mark_pair in ipairs(short_rails) do
		saver:add_rail(i, mark_pair)
		if saver.total_size > MAX_SIZE then
			table.insert(files, saver:write())
			saver = SaverEkasui(proezd_params)
		end
		if not dlg:step(i / #short_rails, sprintf('Сохранение рельсов %d / %d', i, #short_rails)) then
			return
		end
	end

	if saver.total_size > 0 then
		table.insert(files, saver:write())
	end
	return files
end

local function report_short_rails_ekasui()
	EnterScope(function(defer)
		local proezd_params = EKASUI.AskEkasuiParam()
		if not proezd_params then return end

		local min_length, show_only_rubki = askUpperRailLen()
		if not min_length then return end

		local dlg = luaiup_helper.ProgressDlg('Отчет ЕКАСУИ')
		defer(dlg.Destroy, dlg)

		local marks = get_marks(dlg)
		local short_rails = scan_for_short_rail(marks, min_length*1000, show_only_rubki)
		local paths_dst = save_short_rails_ekasui(proezd_params, dlg, short_rails)
		local msg = "Сохранены файлы:\n  " .. table.concat(paths_dst, "\n  ")
		local anwser = iup.Alarm("ATape", msg, "Показать", "Конвертировать в HTML", "Закрыть")
		if 1 == anwser and #paths_dst > 1 then
			local cmd = "explorer.exe /select, \"" .. paths_dst[1] .. "\""
			os.execute(cmd)
		end
        if 2 == anwser then
			for _, path_dst in ipairs(paths_dst) do
				os.execute(sprintf("%s//make_short_rail_html.js %s", EKASUI_PARAMS.ExportFolder, path_dst))
			end
		end
	end)
end

local function MakeEkasuiGapReport(mark)
	local template = resty.compile([[
<!DOCTYPE html>
<html>
    <head>
        <META http-equiv="Content-Type" content="text/html">
        <meta charset="utf-8">
        <title>Ведомость оценки стыка</title>
        <style type="text/css">
body {
    font-family: "Times New Roman", "Tahoma", Sans-Serif;
    font-size: 15px;
	width: 500px;
	margin: 20px;
}
.header {
    background-color: blue;
    color: white;
    text-align: center;
    font-weight: 800;
    font-size: 130%;
}
table {
    border-collapse: collapse;
    /* text-align: left; */
    empty-cells: show;
    width: 100%;
}
td {
    border: 1px solid #000;
}
.gap_technical td:nth-child(2) {
    text-align: right;
}
.gap_properties td:nth-child(2) {
    text-align: center;
}
img {
    display: block;
    margin: auto;
}
        </style>
    </head>

    <body>
        <div class="header">
            Ведомость оценки стыка {{gap.km}} км {{gap.m}} м
        </div>
        <br/>
		<b>{{os.date("%d.%m.%Y %H:%M:%S")}}</b>
		<br/>
		{{Passport.DIRECTION}}
        <br/>
        <img src='data:image/jpg;base64,{{image_base64}}'>
        <br/>
        <table class='gap_technical'>
            <tr>
                <td colspan="2">Техническая характеристика стыка</td>
            </tr>
            <tr>
                <td>Тип стыка</td>
                <td>{{gap.gaptype == 0 and 'болтовой' or gap.gaptype == 1 and 'изолированный' or gap.gaptype == 2 and 'сварной' or gap.gaptype}}</td>
            </tr>
            <tr>
                <td>Тип накладки</td>
                <td>{{gap.nakltype == 1 and 'шестидырная' or gap.nakltype == 2 and 'четырехдырная накладка' or gap.nakltype or ""}}</td>
            </tr>
            <tr>
                <td>Тип скрепления</td>
                <td></td>
            </tr>
            <tr>
                <td>Тип шпал</td>
                <td>{{gap.shpal_material == 1 and 'ЖБШ' or 'ДШ'}}</td>
            </tr>
        </table>
        <br/>
        <table class='gap_properties'>
            <tr>
                <td>Наименование</td>
                <td>Величина параметра</td>
            </tr>
            <tr>
                <td>Просадки в зоне стыка</td>
                <td></td>
            </tr>
            <tr>
                <td>Величина стыкового зазора</td>
                <td>{{gap.zazor}}</td>
            </tr>
            <tr>
                <td>Вертикальный уступ</td>
                <td></td>
            </tr>
            <tr>
                <td>Горизонтальный уступ</td>
                <td>{{gap.gstup}}</td>
            </tr>
            <tr>
                <td>Смятие головки рельсы в зоне стыка (дефект)</td>
                <td></td>
            </tr>
            <tr>
                <td>Дефекты рельсовой накладки <i>(надрыв трещина излом)</i></td>
                <td></td>
            </tr>
            <tr>
                <td>Отсутствие стыковых болтов</td>
                <td>{{gap.bolt}}</td>
            </tr>
            <tr>
                <td>Выплеск балласта</td>
                <td></td>
            </tr>
            <tr>
                <td>Отсутствующие или негодные скрепления</td>
                <td>{{gap.skrepl or ''}}</td>
            </tr>
            <tr>
                <td>Отсутствующие или негодные накладки <i>(выход подошвы рельса из реборд накладок)</i></td>
                <td>{{gap.nakl or ''}}</td>
            </tr>
            <tr>
                <td>Наличие негодных шпал в зоне стыка</td>
                <td>{{gap.shpal or ''}}</td>
            </tr>
            <tr>
                <td>Отклонение от эпюрных значений укладки деревянных или железобетонных шпал <i>(брусьев)</i></td>
                <td></td>
            </tr>
            <tr>
                <td>Недостаточное, избыточное количество балласта в шпальных ящиках</td>
                <td></td>
            </tr>
            <tr>
                <td>Не вскрытый стык от снега <i>(в зимний период)</i></td>
                <td></td>
            </tr>
            <tr>
                <td>Величина комплексного показателя <b>Кк</b></td>
                <td></td>
            </tr>
        </table>
    </body>
</html>
	]])
	ShowVideo = 1 -- global
	local gap_params = make_gap_description(mark)
	local html = template({image_base64=gap_params.img_data, gap=gap_params.values, Passport=Passport})
	local file_path = string.format("%s\\gap_report_%s.%d.%s.html", os.getenv('tmp'), Passport.SOURCE, mark.prop.SysCoord, os.date('%y%m%d-%H%M%S'))
	local file = assert(io.open(file_path, 'w+b'))
	file:write(html)
	file:close()
	os.execute(file_path)
end

-- =============================================== --

local name_prefix = "КОС (компл. оценка стыка)|"

local cur_reports =
{
	{
		name = name_prefix .. "Excel",
		fn = report_short_rails_excel,
		params = {filename="Scripts\\ProcessSum.xlsm", sheetname="Рубки"},
		guids = joints_guids,
	},
	{
		name = name_prefix .. "ЕКАСУИ",
		fn = report_short_rails_ekasui,
		guids = joints_guids,
	},
}

-- тестирование
if not ATAPE then

	local test_report  = require('local_data_driver')
	local d = test_report.Driver("C:\\Avikon\\CheckAvikonReports\\data\\data_27_long.xml")

	--local data_path = 'D:/ATapeXP/Main/494/video_recog/2019_05_17/Avikon-03M/30346/[494]_2019_03_15_01.xml'
	local data_path = 'D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml'
	-- local data_path = 'D:\\Downloads\\722\\492 dlt xml sum\\[492]_2021_03_16_01.xml'
	--local data_path = 'D:\\d-drive\\ATapeXP\\Main\\test\\1\\[987]_2020_11_30_01.xml'
	-- local data_path = 'D:\\Downloads\\742\\[498]_2021_04_29_38.xml'

	-- отчет ЕКАСУИ
	if  1 == 1 then
		--local r = cur_reports[1] -- отчет Excel
		local r = cur_reports[2] -- отчет ЕКАСУИ
		r.fn(r.params)
	end

	-- ведомость стыка
	if 0 == 1 then
		local mark = Driver:GetMarks({mark_id=3})[1]
		MakeEkasuiGapReport(mark)
	end
end

return
{
	AppendReports = function (reports)
		for _, report in ipairs(cur_reports) do
			table.insert(reports, report)
		end
	end,
	MakeEkasuiGapReport = MakeEkasuiGapReport,
}