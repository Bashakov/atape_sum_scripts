if not ATAPE then
	require "luacom"
end

stuff = require 'stuff'
OOP = require 'OOP'

-- ======================  stuff  ============================= -- 

-- перекодировка из utf8 (использующейся тут в скрипте) в cp1251 (для передачи в os.execute)
-- https://stackoverflow.com/questions/41855842/converting-utf-8-string-to-ascii-in-pure-lua
function utf8_cp1251(utf8str)
	--[[
	rr = []
	for ch in range(128, 256):
		try:
			b = bytes([ch])
			s = b.decode('cp1251')
			u = s.encode('utf8')
			if len(u) > 2: continue
			# print(ch, s, b, u, ord(s))
			r = "[0x%04x] = 0x%x" % (ord(s), ch)
			# print(r)
			rr.append(r)
		except UnicodeDecodeError:
			# print(ch)
			pass
	print(', '.join(rr))
	]]
	local code_cp1251 = {
		[0x0402] = 0x80, [0x0403] = 0x81, [0x0453] = 0x83, [0x0409] = 0x8a, [0x040a] = 0x8c, [0x040c] = 0x8d, [0x040b] = 0x8e, [0x040f] = 0x8f, 
		[0x0452] = 0x90, [0x0459] = 0x9a, [0x045a] = 0x9c, [0x045c] = 0x9d, [0x045b] = 0x9e, [0x045f] = 0x9f, [0x00a0] = 0xa0, [0x040e] = 0xa1, 
		[0x045e] = 0xa2, [0x0408] = 0xa3, [0x00a4] = 0xa4, [0x0490] = 0xa5, [0x00a6] = 0xa6, [0x00a7] = 0xa7, [0x0401] = 0xa8, [0x00a9] = 0xa9, 
		[0x0404] = 0xaa, [0x00ab] = 0xab, [0x00ac] = 0xac, [0x00ad] = 0xad, [0x00ae] = 0xae, [0x0407] = 0xaf, [0x00b0] = 0xb0, [0x00b1] = 0xb1, 
		[0x0406] = 0xb2, [0x0456] = 0xb3, [0x0491] = 0xb4, [0x00b5] = 0xb5, [0x00b6] = 0xb6, [0x00b7] = 0xb7, [0x0451] = 0xb8, [0x0454] = 0xba, 
		[0x00bb] = 0xbb, [0x0458] = 0xbc, [0x0405] = 0xbd, [0x0455] = 0xbe, [0x0457] = 0xbf, [0x0410] = 0xc0, [0x0411] = 0xc1, [0x0412] = 0xc2, 
		[0x0413] = 0xc3, [0x0414] = 0xc4, [0x0415] = 0xc5, [0x0416] = 0xc6, [0x0417] = 0xc7, [0x0418] = 0xc8, [0x0419] = 0xc9, [0x041a] = 0xca, 
		[0x041b] = 0xcb, [0x041c] = 0xcc, [0x041d] = 0xcd, [0x041e] = 0xce, [0x041f] = 0xcf, [0x0420] = 0xd0, [0x0421] = 0xd1, [0x0422] = 0xd2, 
		[0x0423] = 0xd3, [0x0424] = 0xd4, [0x0425] = 0xd5, [0x0426] = 0xd6, [0x0427] = 0xd7, [0x0428] = 0xd8, [0x0429] = 0xd9, [0x042a] = 0xda, 
		[0x042b] = 0xdb, [0x042c] = 0xdc, [0x042d] = 0xdd, [0x042e] = 0xde, [0x042f] = 0xdf, [0x0430] = 0xe0, [0x0431] = 0xe1, [0x0432] = 0xe2, 
		[0x0433] = 0xe3, [0x0434] = 0xe4, [0x0435] = 0xe5, [0x0436] = 0xe6, [0x0437] = 0xe7, [0x0438] = 0xe8, [0x0439] = 0xe9, [0x043a] = 0xea, 
		[0x043b] = 0xeb, [0x043c] = 0xec, [0x043d] = 0xed, [0x043e] = 0xee, [0x043f] = 0xef, [0x0440] = 0xf0, [0x0441] = 0xf1, [0x0442] = 0xf2, 
		[0x0443] = 0xf3, [0x0444] = 0xf4, [0x0445] = 0xf5, [0x0446] = 0xf6, [0x0447] = 0xf7, [0x0448] = 0xf8, [0x0449] = 0xf9, [0x044a]	= 0xfa, 
		[0x044b] = 0xfb, [0x044c] = 0xfc, [0x044d] = 0xfd, [0x044e] = 0xfe, [0x044f] = 0xff
	}
	local function utf8_to_unicode(utf8str, pos)
	   local code, size = utf8str:byte(pos), 1
	   if code >= 0xC0 and code < 0xFE then
		  local mask = 64
		  code = code - 128
		  repeat
			 local next_byte = utf8str:byte(pos + size) or 0
			 if next_byte >= 0x80 and next_byte < 0xC0 then
				code, size = (code - mask - 2) * 64 + next_byte, size + 1
			 else
				code, size = utf8str:byte(pos), 1
			 end
			 mask = mask * 32
		  until code < mask
	   end
	   -- returns code, number of bytes in this utf8 char
	   return code, size
	end

	local pos, result = 1, {}
	while pos <= #utf8str do
		local code, size = utf8_to_unicode(utf8str, pos)
		--print(code, size)
		pos = pos + size
		code = code < 128 and code or code_cp1251[code] or ('?'):byte()
		table.insert(result, string.char(code))
	end
	return table.concat(result)
end

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
		elseif sheet.name ~= "STOP" then
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

-- https://docs.microsoft.com/ru-ru/office/vba/api/excel.xlcalculation
local XlCalculation = 
{
	xlCalculationAutomatic 		=	-4105, 	-- Excel controls recalculation.
	xlCalculationManual 		=	-4135, 	-- Calculation is done when the user requests it.
	xlCalculationSemiautomatic 	=	2, 		-- Excel controls recalculation but ignores changes in tables.
}

local excel_helper = OOP.class
{
	ctor = function(self, template_path, sheet_name, visible, dest_name)
		
		sheet_name = sheet_name or ""
		self._excel = luacom.CreateObject("Excel.Application") 		-- запустить экземпляр excel
		assert(self._excel, "Error! Could not run EXCEL object!")
		
		self._excel.Visible = visible 								-- сделать его видимым если нужно
		
		self._file_path = CopyTemplate(template_path, sheet_name, dest_name)	-- скопируем шаблон в папку отчетов
		self._workbook = OpenWorkbook(self._excel, self._file_path)	
		assert(self._workbook, stuff.sprintf("can not open %s", self._file_path))
		
		self._worksheet = FindWorkSheet(self._workbook, sheet_name)
		assert(self._worksheet, stuff.sprintf('can not find "%s" worksheet', sheet_name))
		
		self._calc_state = self._excel.Calculation
		self._excel.Calculation = XlCalculation.xlCalculationManual
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
		
		if row_count == 0 then
			user_range.Rows(template_row_num).EntireRow:Delete()
		end
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
		local run_in_another_process = false		
		self._excel.Calculation = self._calc_state
		if(not run_in_another_process) then
			self._excel.visible = true
		end
		self._workbook:Save()
		self._worksheet = nil
		self._workbook = nil
		if(run_in_another_process) then
			self._excel:Quit()
		end
		self._excel = nil
		if(run_in_another_process) then
			print(self._file_path)
			self._file_path = utf8_cp1251(self._file_path)  -- эта строка нужна тк ATape работает в кодировке cp1251
			if(string.find(self._file_path, '%s')) then -- если есть пробелы
				self._file_path = '"" "' .. self._file_path .. '"' 
				-- https://superuser.com/questions/239565/can-i-use-the-start-command-with-spaces-in-the-path
			end
			os.execute('explorer ' .. self._file_path)
		end
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
			
			local row_data = fn_get_templates_data and fn_get_templates_data(mark) or mark
			row_data.N = line
				
			local cell_LT = data_range.Cells(line, 1)
			local cell_RB = data_range.Cells(line, data_range.Columns.count)
			local row_range = user_range:Range(cell_LT, cell_RB)

			self:ReplaceTemplates(row_range, {row_data})
			if dlgProgress and not dlgProgress:step(line / dst_row_count, stuff.sprintf('Сохранение %d / %d', line, dst_row_count)) then 
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
			local row_data = fn_get_templates_data and fn_get_templates_data(mark) or mark
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
	
	point2pixel =  function(excel, points)
		-- перевод точек excel в пиксели
		-- https://stackoverflow.com/questions/29402407/how-to-set-excel-column-widths-to-a-certain-number-of-pixels
		local nPointsPerInch = 72.0
		local nPixelsPerInch = excel._workbook.WebOptions.PixelsPerInch
		local pixels = points / nPointsPerInch * nPixelsPerInch
		-- printf('Point2Pixel point = %d, pixel = %d\n', points, pixels)
		return pixels
	end,

	-- удаление не примененных подстановки
	CleanUnknownTemplates = function(self)
		local user_range = self._worksheet.UsedRange
		for r = 1, user_range.Rows.count do						-- по всем строкам
			for c = 1, user_range.Columns.count do				-- и столбцам
				local cell = user_range.Cells(r, c) 
				local val = cell.Value2							-- проверяем ячейку
				if val then
					local val_new = string.gsub(val, '%$([%w_]+)%$', '-') 	-- и заменим шаблон
					if val ~= val_new then
						cell.Value2 = val_new
					end
				end
			end
		end
	end,
}

-- ======================TEST ============================= -- 

if false and not ATAPE then
	local excel = excel_helper('C:\\Users\\abashak\\ATapeReport\\191223-110926_.xls', nil, true)
	--excel:ApplyPassportValues({})
	
	excel:SaveAndShow()
	print('Bye')
end

return excel_helper