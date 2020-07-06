local GUIDS = require "sum_list_pane_guids"
local sumPOV = require "sumPOV"

-- =========== stuff ============== -- 

local function find(array, elem)
	for i, val in ipairs(array) do
		if val == elem then return i end
	end
end

local function create_document()
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	if not xmlDom then error("no Msxml2.DOMDocument: " .. luacom.config.last_error) end
	return xmlDom
end

local function load_xml(path)
	local xmlDom = create_document()
	if not xmlDom:load(path) then error(string.format("Msxml2.DOMDocument load(%s) failed with: %s", path, xmlDom.parseError.reason)) end
	return xmlDom
end

local function parse_xml(strXml)
	local xmlDom = create_document()
	if not xmlDom:loadXml(strXml) then error(string.format("Msxml2.DOMDocument parse failed with: %s", xmlDom.parseError.reason)) end
	return xmlDom
end

local function select_nodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end


local function clear_desc_attrib(xml)
	local names = {'_value', 'value_', '_desc'}
	for _,name in ipairs(names) do
		for n in select_nodes(xml, "//*[@" .. name .. "]") do 
			n:removeAttribute(name) 
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
	local recog_xml = parse_xml(mark.ext.RAWXMLDATA or '<a/>')
	
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
	local function read_bolts(recog_xml)
		local bolts = {}
		for nodeCrewJoint in select_nodes(recog_xml, "//PARAM[@name='ACTION_RESULTS' and @value='CrewJoint']") do
			local nodeCh = nodeCrewJoint.attributes:getNamedItem('channel')
			for nodeJoint in select_nodes(nodeCrewJoint, "PARAM/PARAM/PARAM[@name='JointNumber']") do
				local num = nodeJoint.attributes:getNamedItem('value').nodeValue
				local nodeState = nodeJoint:selectSingleNode("PARAM[@name='CrewJointSafe']/@value")
				local state = tonumber(nodeState.nodeValue)
				if -1 <= state and state <= 3 then
					table.insert(bolts, {ch=nodeCh and tostring(nodeCh.nodeValue) or '', num=num, nodeState=nodeState, state=state+1})
				end
			end
		end
		return bolts
	end
	local mark = obj.mark
	local recog_xml = parse_xml(mark.ext.RAWXMLDATA)
	local bolts = read_bolts(recog_xml)
	local fmt = ''
	local states = {}
	for i, bolt in ipairs(bolts) do
		fmt = fmt .. string.format('Канал %s отв. %s: %%o|нет|болтается|есть|болт|гайка|\n', bolt.ch, bolt.num)
		states[i] = bolt.state
	end
	
	local res = {iup.GetParam("Редактирование болтов", nil, fmt, table.unpack(states))}
	if res[1] then
		for i, bolt in ipairs(bolts) do
			print(res[i+1])
			bolt.nodeState.nodeValue = res[i+1] - 1
		end
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

local function npu_convert(obj)
	local mark = obj.mark
	mark.prop.Guid = obj.guid
	mark:Save()
	return RETURN_STATUS.UPDATE_MARK
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
		sumPOV.RejectDefects(obj.mark, true)
	end
	return RETURN_STATUS.UPDATE_MARK
end

			
-- =============== EXPORT ===============

-- статусы обработки для подсказки таблице отметок как обновлятся
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
	
	if find(GUIDS.recognition_guids, mark_guid) then
		table.insert(menu_items, {name='Редактировать ширину зазора', fn=edit_width, mark=mark})
		if recog_xml and #recog_xml > 0 then
			table.insert(menu_items, {name="Редактировать наличие болтов", fn=edit_bolts, mark=mark})
		end
	end
	
	if find(GUIDS.NPU_guids, mark_guid) then
		table.insert(menu_items, {name='Конвертировать в|Возможн. НПУ', fn=npu_convert, mark=mark, guid="{19FF08BB-C344-495B-82ED-10B6CBAD508F}"})
		table.insert(menu_items, {name='Конвертировать в|Подтвр. НПУ',  fn=npu_convert, mark=mark, guid="{19FF08BB-C344-495B-82ED-10B6CBAD5090}"})
		table.insert(menu_items, {name='Конвертировать в|БС. НПУ',      fn=npu_convert, mark=mark, guid="{19FF08BB-C344-495B-82ED-10B6CBAD5091}"})
	end
	
	table.insert(menu_items, '')
	table.insert(menu_items, {name='Устанавливка состояние флагов ПОВ', fn=sumPOV.ShowSettings}) --  (д.б. открыт нужный видеокомпонент)
	table.insert(menu_items, {name='Сформировать выходную форму видеофиксации', fn=videogram_mark, mark=mark}) --  (д.б. открыт нужный видеокомпонент)
	table.insert(menu_items, {name='Удалить отметку', fn=remove_mark, mark=mark})
	table.insert(menu_items, '')
	-- 4.2.1.4 Редактирование свойств отметки распознавания
	table.insert(menu_items, {name='Подтверждать в ЕКАСУИ', fn=accept_pov, mark=mark, method=0, CHECKED=sumPOV.IsAcceptEKASUI(mark)})
	table.insert(menu_items, {name='Подтвердить', fn=accept_pov, mark=mark, method=1})
	table.insert(menu_items, {name='Подтвердить*', fn=accept_pov, mark=mark, method=2})
	table.insert(menu_items, {name='Ввести пользовательский', fn=accept_pov, mark=mark, method=3})
	table.insert(menu_items, {name='Отвергнуть дефектность', fn=accept_pov, mark=mark, method=4})
	
	return menu_items
end

-- для загрузки как пакета в sum_list_pane.lua
return {
	GetMenuItems = GetMenuItems,
	RETURN_STATUS = RETURN_STATUS
} 
