if not ATAPE then
	require "luacom"
end

stuff = require 'stuff'
OOP = require 'OOP'

-- ======================  stuff  ============================= -- 

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
	local path, name = SplitPath(dst)
	path = CreatePath(path) 
	assert(dst == path .. name)
	
	fso:CopyFile(src, dst, True)
	return fso:FileExists(dst)
end

local function CopyTemplate(template_path, sheet_name)		-- скопировать файл шаблона в папку отчетов
	local new_name = os.getenv('USERPROFILE') .. '\\ATapeReport\\' .. os.date('%y%m%d-%H%M%S ') .. sheet_name .. '.xls'
	if not CopyFile(template_path, new_name) then
		stuff.errorf('copy file %s -> %s failed', template_path, new_name)
	end
	return new_name
end

local function OpenWorkbook(excel, file_path)
	local workbooks = excel.Workbooks						
	
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
		if sheet.name == sheet_name then
			worksheet = sheet								-- сохраняем для использования
			worksheet:Activate()							-- и активируем его
		else
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

local function FindTemplateRowNum(user_range)
	for r = 1, user_range.Rows.count do						-- по всем строкам
		local val = user_range.Cells(r, 1).Value2			-- проверяем первую ячейку
		local replaced, found = string.gsub(val or '', '%%table%%', '')
		if found ~= 0 then
			user_range.Cells(r, 1).Value2 = replaced		-- если нашли, то уберем маркер
			return r
		end
	end
end


-- ======================  EXCEL  ============================= -- 


excel_helper = OOP.class
{
	ctor = function(self, template_path, sheet_name, visible)
		self._excel = luacom.CreateObject("Excel.Application") 		-- запустить экземпляр excel
		assert(self._excel, "Error! Could not run EXCEL object!")
		
		self._excel.Visible = visible 								-- сделать его видимым если нужно
		
		local file_path = CopyTemplate(template_path, sheet_name)	-- скопируем шаблон в папку отчетов
		
		self._workbook = OpenWorkbook(self._excel, file_path)	
		assert(self._workbook, stuff.sprintf("can not open %s", file_path))
		
		self._worksheet = FindWorkSheet(self._workbook, sheet_name)
		assert(self._worksheet, stuff.sprintf('can not find "%s" worksheet', sheet_name))
	end,

	ApplyPassportValues = function(self, psp)						-- заменить строки вида $START_KM$ на значения из паспорта
		local user_range = self._worksheet.UsedRange
		for n = 1, user_range.Cells.count do						-- пройдем по всем ячейкам	
			local cell = user_range.Cells(n);
			local val = cell.Value2		
			if val then
				local replaced, found = string.gsub(val, '%$([%w_]+)%$', psp) -- и заменим шаблон
				if found > 0 then
					cell.Value2 = replaced							-- вставим исправленной значение
				end
			end
		end
	end,

	CloneTemplateRow = function(self, row_count)
		local user_range = self._worksheet.UsedRange				-- возьмем пользовательский диаппазон (ограничен незаполненными ячейками, и имеет свою внутреннюю адресацию)
		
		local template_row_num = FindTemplateRowNum(user_range)		-- номер шаблона строки с данными
		assert(template_row_num, 'Can not find table marker in tempalate')

		if row_count > 1 then
			local row_template = user_range.Rows(template_row_num+1).EntireRow -- возьмем строку (включая размеремы EntireRow)
			row_template:Resize(row_count-1):Insert()				-- размножим ее
		end
		
		self._data_range = self._worksheet:Range(					-- сделаем из них новый диаппазон
			user_range.Cells(template_row_num, 1), 
			user_range.Cells(template_row_num + row_count - 1, user_range.Columns.count-1))
		
		if row_count > 1 then
			for c = 1, user_range.Columns.count do
				self._data_range.Columns(c):FillDown()				-- а затем заполним его включая значения и форматирования на основе первой строки (шаблона)
			end
		end
		
		return self._data_range
	end,

	InsertLink = function (self, cell, url, text)					-- вставка ссылки в ячейку
		local hyperlinks = cell.worksheet.Hyperlinks
		--local hyperlinks = self._worksheet.Hyperlinks
		-- print(cell.row, cell.column)
		hyperlinks:Add(cell, url, nil, nil, tostring(text or url))
	end,

	InsertImage = function(self, cell, img_path)					-- вставка изображения в ячейку
		local XlPlacement = 
		{
			xlFreeFloating = 3,
			xlMove = 2,
			xlMoveAndSize = 1,
		}
	
		local ok, err = pcall(function() 
			local shapes = cell.worksheet.Shapes
			--local shapes = self._worksheet.Shapes
			-- print(cell.row, cell.column, cell.Left, cell.Top, cell.Width, cell.Height)
			local picture = shapes:AddPicture(img_path, false, true, cell.Left, cell.Top, cell.Width, cell.Height);
			picture.Placement = XlPlacement.xlMoveAndSize
		end)
	
		if not ok then
			cell.Value2 = err
		end
	end,
	
	AutoFitDataRows = function(self)
		self._data_range.Rows:AutoFit()
	end,
	
	SaveAndShow = function(self)
		self._excel.visible = true
		self._workbook:Save()
	end,
	
}

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
	local img_list = io.open('C:\\Users\\abashak\\Desktop\\lua_test\\image_list.txt')
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


local function ProcessMarks(excel, data_range, marks)					-- вставка отметок в строки
	if marks then 
		assert(#marks == data_range.Rows.count, 'misamtch count of marks and table rows')
		
		for i = 1, #marks do									-- продем по отметкам
			local mark = marks[i]
			data_range.Cells(i, 1).Value2 = mark.sysCoord
			data_range.Cells(i, 4).Value2 = mark.desc
			data_range.Cells(i, 6).Value2 = "wwwww"
			
			excel:InsertImage(data_range.Cells(i, 8), mark.img_path)
			excel:InsertLink(data_range.Cells(i, 10), 'http://google.com', 'google')
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

if false and not ATAPE then

	psp = test_helper.Passport2Table('C:\\Users\\abashak\\Desktop\\lua_test\\[480]_2014_03_19_01.xml')
	marks = test_helper.GenerateTestMarks(4)

	excel = excel_helper('C:\\Users\\abashak\\Desktop\\lua_test\\ProcessSum.xls', 'Ведомость Зазоров', true)
	excel:ApplyPassportValues(psp)
	local data_range = excel:CloneTemplateRow(#marks)

	ProcessMarks(excel, data_range, marks)
	--excel:AutoFitDataRows()
end

return excel_helper