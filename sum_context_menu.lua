-- =========== stuff ============== -- 

local function make_closure(fn, ...)
	local params = {...}
	return function(obj) return fn(obj, table.unpack(params)) end
end

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

-- ================================== -- 

-- открыть xml распознавания в редакторе
local function show_mark_xml(obj)
	local mark = obj.mark
	local str_xml = mark.ext.RAWXMLDATA
	
	local file_path = os.getenv('tmp') .. "\\recognition_result_" .. os.date('%y%m%d-%H%M%S') .. ".xml"
	local f = assert(io.open(file_path, 'w+b'))
	f:write(str_xml)
	f:close()
	
	os.execute(file_path)
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
	local recog_xml = mark.ext.RAWXMLDATA
	local mark_guid = mark.prop.Guid

	if recog_xml and #recog_xml > 0 then
		table.insert(menu_items, {name="Показать XML распознавания", fn=show_mark_xml, mark=mark})
	end
	
	if find({"{CBD41D28-9308-4FEC-A330-35EAED9FC801}", 
			 "{CBD41D28-9308-4FEC-A330-35EAED9FC802}",
			 "{CBD41D28-9308-4FEC-A330-35EAED9FC803}",
			 "{CBD41D28-9308-4FEC-A330-35EAED9FC804}",}, mark_guid) then
		table.insert(menu_items, {name='Редактировать ширину зазора', fn=edit_width, mark=mark})
	end
	
	table.insert(menu_items, {name='Удалить отметку', fn=remove_mark, mark=mark})

	return menu_items
end

-- для загрузки как пакета в sum_list_pane.lua
return {
	GetMenuItems = GetMenuItems,
	RETURN_STATUS = RETURN_STATUS
} 
