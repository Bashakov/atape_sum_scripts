if not ATAPE then
	require "luacom"
end

stuff = require 'stuff'
OOP = require 'OOP'

-- ======================  stuff  ============================= -- 

-- проход по таблице в сортированном порядке 
local function sorted(tbl)
	local keys = {}
	for n, _ in pairs(tbl) do table.insert(keys, n) end
	table.sort(keys)
	local i = 0
	return function()
		i = i + 1
		return keys[i], tbl[keys[i]]
	end
end

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
		stuff.errorf("template %s not exist", src)
	end
	
	local path, name = SplitPath(dst)
	path = CreatePath(path) 
	assert(dst == path .. name)
	fso:CopyFile(src, dst, True)
	return fso:FileExists(dst)
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
	
	local new_name = os.getenv('USERPROFILE') .. '\\ATapeReport\\' .. file_name .. '.xls'
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
		if not sheet_name or #sheet_name == 0 or sheet.name == sheet_name then
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
		for c = 1, user_range.Columns.count do
			local val = user_range.Cells(r, c).Value2			-- проверяем ячейку
			-- print(r, c, val)
			for _, table_marker in ipairs{'%%table%%', '%$table%$'} do
				local replaced, found = string.gsub(val or '', table_marker, '')
				if found ~= 0 then
					user_range.Cells(r, 1).Value2 = replaced		-- если нашли, то уберем маркер
					return r
				end
			end
		end
	end
end


-- ======================  EXCEL  ============================= -- 


excel_helper = OOP.class
{
	ctor = function(self, template_path, sheet_name, visible, dest_name)
		
		sheet_name = sheet_name or ""
		self._excel = luacom.CreateObject("Excel.Application") 		-- запустить экземпляр excel
		assert(self._excel, "Error! Could not run EXCEL object!")
		
		self._excel.Visible = visible 								-- сделать его видимым если нужно
		
		local file_path = CopyTemplate(template_path, sheet_name, dest_name)	-- скопируем шаблон в папку отчетов
		
		self._workbook = OpenWorkbook(self._excel, file_path)	
		assert(self._workbook, stuff.sprintf("can not open %s", file_path))
		
		self._worksheet = FindWorkSheet(self._workbook, sheet_name)
		assert(self._worksheet, stuff.sprintf('can not find "%s" worksheet', sheet_name))
	end,

	-- проити по всему диаппазону и заменить подстановки
	-- sources_values - массив таблиц со значениями
	ReplaceTemplates = function(self, dst_range, sources_values)
		assert(type(sources_values[1]) == 'table')
			
		for n = 1, dst_range.Cells.count do						-- пройдем по всем ячейкам	
			local cell = dst_range.Cells(n);
			local val = cell.Value2	
			if val then
				for _, src in ipairs(sources_values) do
					val, _ = string.gsub(val, '%$([%w_]+)%$', src) -- и заменим шаблон
				end
				--print(n, cell.Value2, val)
				cell.Value2 = val
			end
		end
	end,

	ApplyPassportValues = function(self, psp)						-- заменить строки вида $START_KM$ на значения из паспорта
		local user_range = self._worksheet.UsedRange
		self:ReplaceTemplates(user_range, {psp})
	end,

	CloneTemplateRow = function(self, row_count, correction)
		correction = correction or 0
		local user_range = self._worksheet.UsedRange				-- возьмем пользовательский диаппазон (ограничен незаполненными ячейками, и имеет свою внутреннюю адресацию)
		
		local template_row_num = FindTemplateRowNum(user_range)		-- номер шаблона строки с данными
		assert(template_row_num, 'Can not find table marker in tempalate')
		template_row_num = template_row_num + correction
		
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
		
		return self._data_range, user_range
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
			local picture = shapes:AddPicture(img_path, false, true, cell.Left, cell.Top, cell.MergeArea.Width, cell.MergeArea.Height)
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
	
	-- поиск диапазона с шаблоном таблицы, возвращает пару ячеек левую верхнюю и правую нижнюю
	ScanTemplateTableRange = function (self, worksheet)
		local templates = {'table_begin', 'table_end'}
		local cells = {}
		local user_range = worksheet.UsedRange
		for n = 1, user_range.Cells.count do						-- пройдем по всем ячейкам	
			local cell = user_range.Cells(n);
			local val = cell.Value2	
			if val then
				for i, tmp in ipairs(templates) do
					val, found = string.gsub(val, '%%' .. tmp .. '%%', '') -- и заменим шаблон
					if found ~= 0 then
						cells[i] = cell
					end
				end
				--print(n, cell.Value2, val)
				cell.Value2 = val
			end
		end
		assert(cells[1], 'Can not find table_begin marker')
		assert(cells[2], 'Can not find table_end marker')
		return cells[1], cells[2]
	end,

	-- генератор, для использования в цикле for, возвращает номер и диапазон, куда следует вставлять данные
	EnumDstTable = function(self, count, progress_callback)
		local const = {
			xlDown = -4121,
			xlShiftToRight = -4161
		}
		
		local worksheet = self._worksheet
		local c1, c2 = self:ScanTemplateTableRange(worksheet) -- ищем шаблонную таблицу
		
		local src_table = worksheet:Range(c1, c2)
		if count > 1 then
			local a = worksheet.Cells(c2.row+1, c1.column)
			local dst_range = a:Resize(src_table.Rows.count * (count-1), src_table.Columns.count)
			dst_range:Insert(const.xlDown)
		end
		
		local function get_table(i) -- функция возвращает диапазон относящийся к требуемой записи (1 <= i <= count)
			local a1 = worksheet.Cells(c1.row + (i-1)*src_table.Rows.count, c1.column)
			local a2 = worksheet.Cells(c1.row + (i+0)*src_table.Rows.count, c2.column)
			local tbl = worksheet:Range(a1, a2)
			return tbl
		end
		
		for i = 2, count do -- проходим по скопированным таблицам вставляем туда щаблон и исправляем высоты
			local dst_table = get_table(i)
			src_table:Copy(dst_table)
			for r = 1, src_table.Rows.count do
				dst_table.Rows(r).RowHeight = src_table.Rows(r).RowHeight
			end
			if progress_callback then
				progress_callback(i, count)
			end
		end
		
		return function(_, i) -- замыкание для for
			i = i + 1
			if i <= count then
				return i, get_table(i)
			end
		end, 0, 0
	end,
	
	-- клонируем шаблонную строку нужное число раз, и вставляем данные
	ApplyRows = function (self, marks, fn_get_templates_data, dlgProgress)
		local dst_row_count = #marks
		local data_range, user_range = self:CloneTemplateRow(dst_row_count)
		for line = 1, dst_row_count do 
			local mark = marks[line]
			
			local row_data = fn_get_templates_data(mark)
			row_data.N = line
				
			local cell_LT = data_range.Cells(line, 1)
			local cell_RB = data_range.Cells(line, data_range.Columns.count)
			local row_range = user_range:Range(cell_LT, cell_RB)

			self:ReplaceTemplates(row_range, {row_data})
			if dlgProgress and not dlgProgress:step(line / dst_row_count, stuff.sprintf('Save %d / %d mark', line, dst_row_count)) then 
				break
			end
		end
	end,
	
	-- добавить лист с доступными заменителями
	AppendTemplateSheet = function(self, psp, marks, fn_get_templates_data, max_marks_count)
		max_marks_count = max_marks_count or 3
		local workbook = self._workbook
		
		local worksheet = workbook.Sheets:Add(nil, self._worksheet)
		self._worksheet:Activate()
		worksheet.Name = 'Шаблоны'
		local user_range = worksheet.UsedRange
		
		user_range.Columns(1).ColumnWidth = 50
		user_range.Columns(2).ColumnWidth = 50
		
		local row = 1
		for n, v in sorted(psp or {}) do
			user_range.Cells(row, 1).Value2 = n
			local cell = user_range.Cells(row, 2)
			cell.NumberFormat = "@"
			cell.HorizontalAlignment = -4131 --xlLeft
			cell.Value2 = v
				
			row = row + 1
		end
		
		user_range.Cells(row, 1).Value2 = '++++++++++++++++++++++++++++'
		row = row + 1
		
		for i = 1, #marks do
			if i > max_marks_count then break end
			
			local mark = marks[i]
			local row_data = fn_get_templates_data(mark)
			row_data.N = i
		
			for n,v in sorted(row_data) do
				user_range.Cells(row, 1).Value2 = n
				local cell = user_range.Cells(row, 2)
				cell.NumberFormat = "@"
				cell.HorizontalAlignment = -4131 --xlLeft
				cell.Value2 = v
				
				row = row + 1
			end
			
			user_range.Cells(row, 1).Value2 = '-------------------------------'
			row = row + 1
		end
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