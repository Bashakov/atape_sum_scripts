if not ATAPE then
	require "luacom"
end

stuff = require 'stuff'


-- ======================  EXCEL  ============================= -- 

local excel_helper = {}

function excel_helper.CopyTemplate(template_path, dst_name)		-- скопировать файл шаблона в папку отчетов
	dst_name = dst_name or os.date('%y%m%d-%H%M%S.xls')
	
	local new_name = os.getenv('USERPROFILE') .. '\\ATapeReport\\' .. dst_name
	local cmd = stuff.sprintf('echo F | xcopy /Y "%s" "%s"', template_path, new_name)
	if os.execute(cmd) == 0 then
		stuff.errorf('cmd failed: %s', cmd)
	end
	return new_name
end


function excel_helper.GetWorksheet(template_path, sheet_name, visible)
	local excel = luacom.CreateObject("Excel.Application") 	-- запустить экземпляр excel
	assert(excel, "Error! Could not run EXCEL object!")
	
	excel.Visible = visible 								-- сделать его видимым если нужно
	
	local file_path = excel_helper.CopyTemplate(template_path) 			-- скопируем шаблон в папку отчетов
	
	local workbooks = excel.Workbooks						
	local workbook
	for i = 1, workbooks.Count do							-- поищем среди открытых
		local wb = workbooks(i)
		if wb.FullName == file_path then
			workbook = wb
			break
		end
	end
	
	if not workbook then									-- или откроем файл
		workbook = workbooks:Open(file_path)
		assert(workbook, stuff.sprintf("can not open %s", file_path))
	end
	
	local ws2del = {}										-- список листов для удаления
	local worksheet
	for i = 1, workbook.Worksheets.Count do
		local sheet = workbook.Worksheets(i)				-- ищем лист с нужным именем
		-- print(i, sheet.name)
		if sheet.name == sheet_name then
			worksheet = sheet								-- сохраняем для использования
			worksheet:Activate()							-- и активируем его
		else
			table.insert(ws2del, sheet)						-- остальные соберем для удаления
		end
	end
	
	assert(worksheet, stuff.sprintf('can not find %s worksheet', sheet_name))
	
	excel.DisplayAlerts = false;							-- отключим предупреждения
	for _, ws in ipairs(ws2del) do ws:Delete() end			-- удаляем ненужные листы
	excel.DisplayAlerts = true;								-- включим предупреждения обратно
	
	return worksheet
end

function excel_helper.CopyTemplateRow(worksheet, row_add_count, fnCB)
	local user_range = worksheet.UsedRange					-- возьмем пользовательский диаппазон (ограничен незаполненными ячейками, своя внутренняя адресация)
	
	local template_row_num									-- номер шаблона строки с данными
	for r = 1, user_range.Rows.count do						-- по всем строкам
		local val = user_range.Cells(r, 1).Value2			-- проверяем первую ячейку
		local replaced, found = string.gsub(val or '', '%%table%%', '')
		if found ~= 0 then
			user_range.Cells(r, 1).Value2 = replaced		-- если нашли, то уберем маркер
			template_row_num = r							-- и сохраним номер
			break;
		end
	end
	
	assert(template_row_num, 'Can not find table marker in tempalate')

	local row_template = user_range.Rows(template_row_num+1).EntireRow -- возьмем строку включая размерамы (EntireRow)
	row_template:Resize(row_add_count-1):Insert()			-- размножим ее
	
	local data_range = worksheet:Range(						-- седлаем из них новый диаппазон
		user_range.Cells(template_row_num, 1), 
		user_range.Cells(template_row_num + row_add_count - 1, user_range.Columns.count-1))
	
	for c = 1, user_range.Columns.count do
		data_range.Columns(c):FillDown()					-- а затем заполним его включая значения и форматирования на основе первой строки (шаблона)
	end
	
	-- for i = 1, row_add_count-1 do							-- размножим строку нужное количество раз
		-- local row_template = user_range.Rows(template_row_num).EntireRow
		-- row_template:Copy()
		-- row_template:Insert()
		-- if fnCB and not fnCB(i) then
			-- row_add_count = i
			-- break
		-- end
	-- end
	
	-- local data_range = worksheet:Range(
		-- user_range.Cells(template_row_num, 1), 
		-- user_range.Cells(template_row_num + row_add_count - 1, user_range.Columns.count-1))
		
	return data_range										-- и вернем диаппазон только этих размноженных ячеек
end

	
function excel_helper.ProcessPspValues(worksheet, psp)				-- заменить строки вида $START_KM$ на значения из паспорта
	local user_range = worksheet.UsedRange
	for n = 1, user_range.Cells.count do					-- пройдем по всем ячейкам	
		local cell = user_range.Cells(n);
		local val = cell.Value2		
		if val then
			local replaced, found = string.gsub(val or '', '%$([%w_]+)%$', psp) -- и заменим шаблон
			if found ~= 0 then
				cell.Value2 = replaced						-- вставим исправленной значение
			end
		end
	end
end

function  excel_helper.InsertLink(cell, url, text)						-- вставка ссылки в ячейку
	local hyperlinks = cell.worksheet.Hyperlinks
	-- print(cell.row, cell.column)
	hyperlinks:Add(cell, url, nil, nil, text or url)
end

function  excel_helper.InsetImage(cell, img_path)						-- вставка изображения в ячейку
	local ok, err = pcall(function() 
		local shapes = cell.worksheet.Shapes;
		-- print(cell.row, cell.column, cell.Left, cell.Top, cell.Width, cell.Height)
		local picture = shapes:AddPicture(img_path, false, true, cell.Left, cell.Top, cell.Width, cell.Height);
		picture.Placement = 1  
	
--		enum XlPlacement
--		{
--			xlFreeFloating = 3,
--			xlMove = 2,
--			xlMoveAndSize = 1
--		};
	end)
	if not ok then
		cell.Value2 = err
	end
end

-- ======================  TEST HELPERS  ============================= -- 

local test_helper = {}

function test_helper.Passport2Table(psp_path)						-- открыть xml паспорт и сохранить в таблицу его свойства
	xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom, 'can not create MSXML object')
	assert(xmlDom:load(psp_path), "can not open xml file: " .. psp_path)
	
	local function parse_attr(node) 						-- извлечение значений из атрибута
		return node.nodeName, node.nodeValue 
	end
	local function parse_item(name, value)					-- извлеченеи значений из ноды по именам атрибутов
		return function(node)
			return node.attributes:getNamedItem(name).nodeValue, node.attributes:getNamedItem(value).nodeValue  
		end
	end
	
	local requests = {
		{path = "/DATA_SET/DRIVER/@*",									fn = parse_attr },
		{path = "/DATA_SET/DEVICE/@*",									fn = parse_attr },
		{path = "/DATA_SET/REGISTRATION_DATA/@*",						fn = parse_attr },
		{path = "/DATA_SET/REGISTRATION_DATA/DATA[@INNER and @VALUE]", 	fn = parse_item('INNER', 'VALUE')},
	}
	
	local res = {}
	for _, req in ipairs(requests) do
		local nodes = xmlDom:SelectNodes(req.path)
		while true do
			local node = nodes:nextNode()
			if not node then break end
			local name, value = req.fn(node)
			-- print(name, value)
			res[name] = value
		end
	end
	return res
end


function test_helper.GenerateTestMarks(cnt)									-- генерация тестовых отметок
	local img_list = io.open('image_list.txt')
	local marks = {}
	for i = 1, cnt do
		local mark = {
			desc =  'desc: ' .. tostring(i), 
			sysCoord = i * 10000, 
			img_path = 'C:\\1\\report_imgs\\' .. img_list:read(),
		}
		marks[i] = mark
	end
	img_list:close()
	return marks
end


local function ProcessMarks(marks, data_range)					-- вставка отметок в строки
	if marks then 
		assert(#marks == data_range.Rows.count, 'misamtch count of marks and table rows')
		
		for i = 1, #marks do									-- продем по отметкам
			local mark = marks[i]
			data_range.Cells(i, 1).Value2 = mark.sysCoord
			data_range.Cells(i, 4).Value2 = mark.desc
			data_range.Cells(i, 6).Value2 = "wwwww"
			
			excel_helper.InsetImage(data_range.Cells(i, 8), mark.img_path)
			excel_helper.InsertLink(data_range.Cells(i, 10), 'http://google.com', 'google')
		end
	else														-- test
		for r = 1, data_range.Rows.count do
			for c = 1, data_range.Columns.count do
				data_range.Cells(i, c).Value2 = stuff.sprintf('r=%s, c=%d', i, c)
			end
		end
	end
end

-- ======================TEST ============================= -- 

if not ATAPE then

	psp = test_helper.Passport2Table('[480]_2014_03_19_01.xml')
	marks = test_helper.GenerateTestMarks(4)

	local worksheet = excel_helper.GetWorksheet('C:\\Users\\abashak\\Desktop\\lua_test\\ProcessSum.xls', 'Ведомость Зазоров', true)
	excel_helper.ProcessPspValues(worksheet, psp)
	local data_range = excel_helper.CopyTemplateRow(worksheet, #marks)

	ProcessMarks(marks, data_range)
end

return excel_helper