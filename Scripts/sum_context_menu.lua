local GUIDS = require "sum_list_pane_guids"
local sumPOV = require "sumPOV"
local rubki = require "sum_report_rubki"
local mark_helper = require 'sum_mark_helper'
local TYPES = require 'sum_types'
local alg = require 'algorithm'
local xml = require 'xml_utils'

-- =========== stuff ============== --

local function clear_desc_attrib(root)
	local names = {'_value', 'value_', '_desc'}
	for _, name in ipairs(names) do
		for n in xml.SelectNodes(root, "//*[@" .. name .. "]") do
			n:removeAttribute(name)
		end
	end
end

local function makeJointEditDlg(toggles, save_fn)
	local label = iup.label {
		title = "\z
			Корректировка наличия болтов:\n\z
			Галочка отмечена -  есть.\n\z
			Галочка отмечена(серая) - ослаблен или нетиповой.\n\z
			Галочка снята - нет."
	}
	local btn_size="60x15"
	local button_ok = iup.button{title="Сохранить", size=btn_size, action = save_fn}
	local button_cancel = iup.button{title="Отмена", size=btn_size, action = function() return iup.CLOSE end}

	local layout = iup.vbox{
		label,
		iup.vbox(toggles),
		iup.hbox{iup.fill{}, button_ok, button_cancel},
	}
	local dlg = iup.dialog{
		layout,
		title = "Редактирование болтов",
		margin="19x5",
		gap="5",
		resize="NO",
		defaultenter = button_ok,
		defaultesc = button_cancel,
	}
	return dlg
end

local function showJointEditDlg(bolts)
	local function safe2toggle(safe)
		if safe == 0 or safe == 4 then -- болтается или нетиповой
			return "NOTDEF"
		elseif safe == 1 or safe == 2 or safe == 3 then -- есть|болт|гайка
			return "ON"
		else
			return "OFF"
		end
	end

	local result = false
	local toggles = {}
	for num, joint_state in ipairs(bolts) do
		toggles[num] = iup.toggle {
			title = string.format("Болтовое отверстие %d", num),
			["3STATE"] = "YES",
			value=safe2toggle(joint_state)
		}
	end

	if #toggles > 0 then
		local function save(self)
			result = true
			local tbl = {["OFF"] = -1, ["NOTDEF"] = 0, ["ON"] = 1}
			for num, toggle in ipairs(toggles) do
				bolts[num] = tbl[toggle.value]
			end
			return iup.CLOSE
		end

		local dlg = makeJointEditDlg(toggles, save)
		dlg:popup()
	end
	return result
end

local function save_bolts(root, bolts)
	for _, num, prev_safe, node_safe in mark_helper.EnumCrewJoint(root) do
		local new_safe = bolts[num+1]
		if new_safe == 1 and (prev_safe == 2 or prev_safe == 3) then
			-- skip
		elseif new_safe == 0 and prev_safe == 4 then
			-- skip
		elseif new_safe == prev_safe then
			-- skip
		else
			node_safe.nodeValue = tostring(new_safe)
		end
	end
end

-- ================================== --

-- открыть xml распознавания в редакторе
local function show_mark_xml(obj)
	local mark = obj.mark
	local str_xml = mark.ext.RAWXMLDATA

	local file_path = os.getenv('tmp') .. "\\recognition_result_" .. os.date('%y%m%d-%H%M%S') .. ".xml"
	local f = assert(io.open(file_path, 'w+b'))
	f:write(str_xml)
	f:close()

	os.execute('start ' .. file_path)
end

local function edit_width(obj)
	local mark = obj.mark
	local recog_xml = xml.load_xml_str(mark.ext.RAWXMLDATA or '<a/>')

	local function gw(propExt, xmlAttr)
		if mark.ext[propExt] then
			return mark.ext[propExt]
		end
		local r = "ACTION_RESULTS/PARAM[@value='" .. xmlAttr .. "']/PARAM[@name='FrameNumber' and @value='0']/PARAM[@name='Result' and @value='main']/PARAM[@name='RailGapWidth_mkm' and @value]/@value"
		local nv = recog_xml:selectSingleNode(r)
		if nv then
			return (nv.nodeValue) / 1000
		end
		return 0
	end

	local wt = gw('VIDEOIDENTGWT', 'CalcRailGap_Head_Top')
	local ws = gw('VIDEOIDENTGWS', 'CalcRailGap_Head_Side')

	res, wt, ws = iup.GetParam(
		'Корректировка ширины', nil, "\z
		Ширина зазора Top (мм): %i[0,100]\n\z
		Ширина зазора Side (мм): %i[0,100]\n",
		wt, ws)

	if res then
		mark.ext['VIDEOIDENTGWT'] = wt
		mark.ext['VIDEOIDENTGWS'] = ws
		sumPOV.UpdateMarks(mark, false)
		mark:Save()
		return RETURN_STATUS.UPDATE_MARK
	end
end

local function edit_bolts(obj)
	local mark = obj.mark
	local recog_xml = xml.load_xml_str(mark.ext.RAWXMLDATA)
	local bolts = mark_helper.GetCrewJointArray(recog_xml)

	if showJointEditDlg(bolts) then
		save_bolts(recog_xml, bolts)
		clear_desc_attrib(recog_xml)
		mark.ext.RAWXMLDATA = recog_xml.xml
		sumPOV.UpdateMarks(mark, false)
		mark:Save()
		return RETURN_STATUS.UPDATE_MARK
	end
end	

local function remove_mark(obj)
	local mark = obj.mark
	if 1 == iup.Alarm("ATape", "Подтвердите удаление отметки", "Да", "Нет") then
		mark:Delete()
		mark:Save()
		return RETURN_STATUS.UPDATE_ALL
	end
end

-- сделать видеограмму
local function videogram_mark(obj)
	local mark = obj.mark
	local sum_videogram = require 'sum_videogram'

	-- work_filter если запускаем из таблицы отметок
	local defect_codes = work_filter and work_filter.videogram_defect_codes
	local videogram_direct_set_defect = work_filter and work_filter.videogram_direct_set_defect
	sum_videogram.MakeVideogram('mark', {mark=mark, defect_codes=defect_codes, direct_set_defect=videogram_direct_set_defect})
end


--[[ 4.2.1.4 Редактирование свойств отметки распознавания

В контекстное меню входят минимально три пункта: Подтвердить, Подтвердить*,
Ввести пользовательский.

- По пункту Подтвердить флаги ПОВ заполняются в соответствии с
	выбранным типом сценария.
- По пункту Подтвердить* пользователю предлагается окно выбора типа ПОВ.
- По пункту Ввести пользовательский пользователю предлагается окно редактирования
	значения (с отображением предыдущего) и выбор флагов ПОВ
	(флаги по умолчанию соответствуют с выбранному сценарию).
]]
local function accept_pov(obj)
	if obj.method == 0 then -- Подтверждать в ЕКАСУИ
		sumPOV.AcceptEKASUI(obj.mark, true, not obj.CHECKED)
	end
	if obj.method == 1 then -- Подтвердить
		sumPOV.UpdateMarks(obj.mark, true)
	end
	if obj.method == 2 then -- Подтвердить*
		if sumPOV.ShowSettings() then
			sumPOV.UpdateMarks(obj.mark, true)
		end
	end
	if obj.method == 3 then -- Ввести пользовательский
		sumPOV.EditMarks(obj.mark, true)
	end
	if obj.method == 4 then -- Отвергнуть дефектность
		local state = sumPOV.IsRejectDefect(obj.mark)
		sumPOV.RejectDefects(obj.mark, true, not state)
	end
	return RETURN_STATUS.UPDATE_MARK
end

-- =============================================

--[[из ТЗ 4.2.1.4
Для Стыковых Зазоров пункт Подтвердить, Подтвердить* разветвляются на три подуровня:
- с нерабочей грани,
- c поверхности катания,
- c рабочей грани.
Отображать в меню текущее значение зазора и предупреждение что остальные зазоры будут удалены. ]]
local function mark_accept_width_checker(menu_items, mark)
	local sides = {
		{sign = 'inactive', lbl = 'с нерабочей грани'},
		{sign = 'thread', lbl = 'c поверхности катания'},
		{sign = 'active', lbl = 'c рабочей грани'},
	}
	for _, side in ipairs(sides) do
		local width = mark_helper.GetGapWidthName(mark, side.sign)
		if width then
			local text = string.format('Подтвердить ширину зазора (удалить остальные)|%s (%d мм)', side.lbl, width)
			local fn = function ()
				mark.ext['VIDEOIDENTGWT'] = width
				mark.ext['VIDEOIDENTGWS'] = width
				sumPOV.UpdateMarks(mark, false)

				if mark.ext.RAWXMLDATA then
					local recog_xml = xml.load_xml_str(mark.ext.RAWXMLDATA)
					for node_width in xml.SelectNodes(recog_xml, "//PARAM[@name='RailGapWidth_mkm' and @value]") do
						local cur_width = tonumber(node_width:SelectSingleNode("@value").nodeValue) / 1000
						if cur_width ~= width then
							local node_result = node_width.parentNode        -- оставить только подтвержденный зазор и
							node_result.parentNode:removeChild(node_result)  -- и его отрисованное значение
							--node_width.parentNode:removeChild(node_width) -- оставить все зазор, но отрисованное значение только у подтвержденного
						end
					end
					clear_desc_attrib(recog_xml)
					mark.ext.RAWXMLDATA = recog_xml.xml
				end
				mark:Save()
				return RETURN_STATUS.UPDATE_MARK
			end
			table.insert(menu_items, {name=text, fn=fn})
		end
	end
end

local function npu_convert(obj)
	local mark = obj.mark
	mark.prop.Guid = obj.guid
	mark:Save()
	return RETURN_STATUS.UPDATE_MARK
end

local function add_npu_tune(menu_items, mark)
	local name_type =
	{
		{name='Возможн. НПУ', guid=TYPES.PRE_NPU},
		{name='Подтвр. НПУ',  guid=TYPES.NPU},
		{name='БС. НПУ',      guid=TYPES.NPU2},
	}
	local prefix = 'Изменить тип НПУ|'

	local is_npu = false
	for _, nt in ipairs(name_type) do
		if nt.guid == mark.prop.Guid then is_npu = true end
	end
	if not is_npu then return false end

	for _, nt in ipairs(name_type) do
		table.insert(menu_items, {
			name = prefix .. nt.name,
			fn = function ()
				mark.prop.Guid = nt.guid
				mark:Save()
				return RETURN_STATUS.UPDATE_MARK
			end,
			CHECKED = (nt.guid == mark.prop.Guid),
			GRAYED = (nt.guid == mark.prop.Guid),
		})
	end
	return true
end

-- =============== EXPORT ===============

-- статусы обработки для подсказки таблице отметок как обновляться
RETURN_STATUS = {
	NONE = 0,
	UPDATE_MARK = 1,
	UPDATE_ALL = 2,
	REMOVE_MARK = 3,
	RELOAD_ALL = 3,
}

--[[ функция вызывается из программы для получения списка элементов меню

должна вернуть массив объектов с обязательными полями "name" и "fn":
- "name" строка - будет отображено в меню, поддерживается формат "lvl1|lvl2|lvl3", в этом случае строятся подменю,
- "fn" функция - будет вызвана при выборе пользователем соотв пункта, в функцию будет передан объект

алгоритм работы атейпа можно описать следующим псевдокодом:

	void on_mark_click(mark)
	{
		CMenu menu;
		vector<script_item> items = GetMenuItems(mark);
		for(item in items)
			menu.add_items(item.name);

		int ixd = menu.Show()
		script_item item = items[ixd];
		item.fn(item);
	}
]]
function GetMenuItems(mark)
	local menu_items = {}
	if not work_filter then -- work_filter определена если функция вызвана из панели отметок, иначе это атейп со своим меню, поэтому добавим 2 разделителя
		table.insert(menu_items, '')
		table.insert(menu_items, '')
	end
	local recog_xml = mark.ext.RAWXMLDATA
	local mark_guid = mark.prop.Guid

	if recog_xml and #recog_xml > 0 then
		table.insert(menu_items, {name="Показать XML распознавания", fn=show_mark_xml, mark=mark})
	end

	if alg.table_find(GUIDS.recognition_guids, mark_guid) then
		table.insert(menu_items, {name='Редактировать ширину зазора', fn=edit_width, mark=mark})
		if recog_xml and #recog_xml > 0 then
			table.insert(menu_items, {name="Редактировать наличие болтов", fn=edit_bolts, mark=mark})
		end
	end

	local npu_mark = add_npu_tune(menu_items, mark)

	table.insert(menu_items, {name='Удалить отметку', fn=remove_mark, mark=mark})

	if not npu_mark then
		table.insert(menu_items, {name='Сформировать выходную форму видеофиксации', fn=videogram_mark, mark=mark}) --  (д.б. открыт нужный видеокомпонент)

		table.insert(menu_items, '')
		table.insert(menu_items, {name='Сценарий: ' .. sumPOV.GetCurrentSettingsDescription(', '), GRAYED=true})
		table.insert(menu_items, {name='Настройка сценария установки ПОВ', fn=sumPOV.ShowSettings})

		table.insert(menu_items, '')

		-- 4.2.1.4 Редактирование свойств отметки распознавания
		table.insert(menu_items, {name='Отметка: ' .. sumPOV.GetMarkDescription(mark, ', '), GRAYED=true})
		table.insert(menu_items, {name='Подтвердить отметку', fn=accept_pov, mark=mark, method=1})
		table.insert(menu_items, {name='Подтвердить отметку не по сценарию установки', fn=accept_pov, mark=mark, method=3})
		mark_accept_width_checker(menu_items, mark)

		if sumPOV.IsRejectDefect(mark) then
			table.insert(menu_items, {name='Вернуть дефектность', fn=accept_pov, mark=mark, method=4})
		else
			table.insert(menu_items, {name='Отвергнуть дефектность (без удаления отметки)', fn=accept_pov, mark=mark, method=4})
		end

		table.insert(menu_items, {name='Ведомость оценки стыка', fn=function () rubki.MakeEkasuiGapReport(mark) end})
	end

	return menu_items
end

-- для загрузки как пакета в sum_list_pane.lua
return {
	GetMenuItems = GetMenuItems,
	EditBold = function (mark) return edit_bolts({mark=mark}) end,
	RETURN_STATUS = RETURN_STATUS
}
