if not ATAPE then
	require "luacom"
end

local OOP = require 'OOP'
local codecs = require 'process_utf8'

local function errorf(s,...)  error(string.format(s, ...)) end
local function sprintf(s,...) return string.format(s, ...) end

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
		errorf("template %s not exist", src)
	end

	local path, name = SplitPath(dst)
	path = CreatePath(path)
	assert(dst == path .. name)
	fso:CopyFile(src, dst, True)
	return fso:FileExists(dst)
end

local function GetFileName(path)
	return path:match("^.+/(.+)$")
end

local function GetFileExtension(path)
	return path:match("^.+(%..+)$")
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

	local user_dir = os.getenv('USERPROFILE') -- возвращает путь кодированный в cp1251, что вызывает ошибку при копировании, тк ожидается utf-8
	user_dir = codecs.cp1251_utf8(user_dir)
	local new_name = user_dir .. '\\ATapeReport\\' .. file_name .. GetFileExtension(template_path)
	if TEST_EXCEL_DST_PATH then
		new_name = TEST_EXCEL_DST_PATH .. GetFileExtension(template_path)
	end
	if not CopyFile(template_path, new_name) then
		errorf('copy file %s -> %s failed', template_path, new_name)
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

-- проход по всем ячейкам, возвращает номер ячейки и саму ячейку
local function cells(range)
	local n = 0
	local cnt = range.Cells.count
	return function ()
		if n < cnt then
			n = n + 1
			return n, range.Cells(n)
		end
	end
end

-- поиск маркера таблицы
local function FindTemplateRowNum(user_range)
	local markers = {
		'%%table%%',
		'%$table%$',
		'%$table_old%$',
		'%$table_rs%$',
	}

	for _, cell in cells(user_range) do
		local val = cell.Value2			-- проверяем ячейку
		-- print(r, c, val)
		for _, table_marker in ipairs(markers) do
			local replaced, found = string.gsub(val or '', table_marker, '')
			if found ~= 0 then
				cell.Value2 = replaced		-- если нашли, то уберем маркер
				return cell.row, table_marker
			end
		end
	end
end

-- применить подстановки в соответствии с переданной таблицей
-- values набор таблиц со значениями
local function apply_values(text, values)
	assert(type(values[1]) == 'table')
	local text_type = type(text)
	if text_type == 'number' then
		return text, false
	elseif text_type == 'string' then -- обычная строка
		if text == '' then
			return text, false
		end
		local orig = text
		for _, val in ipairs(values) do
			text, _ = string.gsub(text, '%$([%w_]+)%$', val) -- и заменим шаблон
		end
		return text, text ~= orig
	elseif text_type == 'table' then -- если передали таблицу, то обработаем каждый элемент
		local change = false
		local res = {}
		for k, v in pairs(text) do
			local vv, c = apply_values(v, values)
			res[k] = vv
			change = change or c
		end
		return res, change
	else
		error('apply_values, unknown src type: ' .. text_type)
	end
end

-- создать recordset с заданным количеством колонок и строками получаемыми из функции
local function generate_recordset_iter(col_count, fn)
	-- https://docs.microsoft.com/en-us/previous-versions/visualstudio/visual-studio-6.0/aa260348(v=vs.60)?redirectedfrom=MSDN
	-- https://docs.microsoft.com/en-us/previous-versions/office/troubleshoot/office-developer/transfer-excel-data-from-ado-recordset
	-- https://powerspreadsheets.com/excel-vba-insert-row/

	local records = luacom.CreateObject("ADODB.Recordset")
	--records.ActiveConnection =  --  = {} -- Nothing
	records.CursorLocation = 3 -- CursorLocationEnum.adUseClient
	records.LockType = 4 -- LockTypeEnum.adLockBatchOptimistic

	local fields = records.Fields
	local columns = {}
	for i = 1, col_count do
		local name = string.format('col_%d', i)
		fields:Append(name, 8) -- DataTypeEnum.adBSTR
		columns[#columns+1] = name
	end

	records:Open()
	local row_num = 1
	while true do
		local data = fn(row_num)
		if not data then
			break
		end
		assert(#data == col_count)
		records:AddNew(columns, data)
		row_num = row_num + 1
	end

	-- print(records.Fields.Count, records.RecordCount)
	-- records:Save("c:/1.xml", 1) -- PersistFormatEnum.adPersistXML

	return records
end

-- ======================  EXCEL  ============================= --

-- https://docs.microsoft.com/ru-ru/office/vba/api/excel.xlcalculation
local XlCalculation =
{
	xlCalculationAutomatic 		=	-4105, 	-- Excel controls recalculation.
	xlCalculationManual 		=	-4135, 	-- Calculation is done when the user requests it.
	xlCalculationSemiautomatic 	=	2, 		-- Excel controls recalculation but ignores changes in tables.
}

local XlInsertShiftDirection =
{
    xlShiftDown					= -4121,
    xlShiftToRight				= -4161
}

local XlInsertFormatOrigin =
{
    xlFormatFromLeftOrAbove = 0,
    xlFormatFromRightOrBelow = 1
};

-- Размножить указанную строку нужное число раз
local function cloneRowCpPs(rng, row_num, req_cnt)
	local cur_cnt = 1
	if req_cnt == 0 then
		rng.Rows(row_num):Delete()
		return
	end

	req_cnt = req_cnt - 1 -- одна строка уже есть
	while req_cnt > 0 do
		local sel_num = math.min(req_cnt, cur_cnt)
		local c1 = rng.Rows(row_num)
		local c2 = rng.Rows(row_num + sel_num - 1)
		local r = rng:Range(c1, c2)
		r:Select()
		r:Copy()
		r:Insert(XlInsertShiftDirection.xlShiftDown)

		req_cnt = req_cnt - cur_cnt
		cur_cnt = cur_cnt * 2
	end

	-- выделим одну строку, чтобы сбросить буфер
	local c = rng.Cells(1, 1)
	c:Copy()
	c:Select()
end

local excel_helper = OOP.class
{
	ctor = function(self, template_path, sheet_name, visible, dest_name)

		sheet_name = sheet_name or ""
		self._excel = luacom.CreateObject("Excel.Application") 		-- запустить экземпляр excel
		assert(self._excel, "Error! Could not run EXCEL object!")

		self._excel.Visible = visible 								-- сделать его видимым если нужно

		self._file_path = CopyTemplate(template_path, sheet_name, dest_name)	-- скопируем шаблон в папку отчетов
		self._workbook = OpenWorkbook(self._excel, self._file_path)
		assert(self._workbook, sprintf("can not open %s", self._file_path))

		self._worksheet = FindWorkSheet(self._workbook, sheet_name)
		assert(self._worksheet, sprintf('can not find "%s" worksheet', sheet_name))

		self._calc_state = self._excel.Calculation
		self._excel.Calculation = XlCalculation.xlCalculationManual
	end,

	-- пройти по всему диапазону и заменить подстановки
	-- sources_values - массив таблиц со значениями
	ReplaceTemplates = function(self, dst_range, sources_values, template_values, fnProgress)
		assert(type(sources_values[1]) == 'table')

		local cell_cnt = dst_range.Cells.count
		for n = 1, cell_cnt do						-- пройдем по всем ячейкам
			local cell = nil
			local val = nil
			if template_values then
				val = template_values[n] or ''
			else
				cell = dst_range.Cells(n)
				val = cell.Value2 or ''
			end

			-- print(n, val, cell.HasFormula, cell.Formula)
			if val ~= '' and not (cell and cell.HasFormula) then
				local res, changed = apply_values(val, sources_values)
				if changed then
					if not cell then
						cell = dst_range.Cells(n)
					end
					cell.Value2 = res
				end
			end
			if fnProgress and not fnProgress(n, cell_cnt) then
				break
			end
		end
	end,

	ApplyPassportValues = function(self, psp, dlg)						-- заменить строки вида $START_KM$ на значения из паспорта
		local user_range = self._worksheet.UsedRange
		local fnProgress = nil
		if dlg then
			fnProgress = function (n, all)
				return
					n % 23 ~= 0 or
					not dlg or
					dlg:step(n / all, sprintf('Применение глобальных значений %d / %d', n, all))
			end
		end
		self:ReplaceTemplates(user_range, {psp}, nil, fnProgress)
	end,

	CloneTemplateRow = function(self, row_count, correction, dlg)
		correction = correction or 0
		local user_range = self._worksheet.UsedRange				-- возьмем пользовательский диаппазон (ограничен незаполненными ячейками, и имеет свою внутреннюю адресацию)

		local template_row_num, marker = FindTemplateRowNum(user_range)		-- номер шаблона строки с данными
		assert(template_row_num, 'Can not find table marker in tempalate')
		template_row_num = template_row_num + correction

		local template_values = {}
		for c = 1, user_range.Columns.count do
			local value = user_range.Cells(template_row_num, c).value2 or ''
			template_values[c] = value
		end

		-- self._excel.Visible = true
		-- self._excel.UserControl = true

		if marker == '%$table_old%$' then
			for i = 1, row_count-1 do
				local row = user_range.Rows(template_row_num + i - 1)
				row:Copy()
				row:Insert(XlInsertShiftDirection.xlShiftDown)

				if dlg and not dlg:step(i / row_count, sprintf('Копирование строк %d / %d', i, row_count)) then
					break
				end

				self._data_range = self._worksheet:Range(					-- сделаем из них новый диаппазон
					user_range.Cells(template_row_num, 1),
					user_range.Cells(template_row_num + row_count - 1, user_range.Columns.count-1))
			end
			if row_count == 1 then -- https://bt.abisoft.spb.ru/view.php?id=760
				self._data_range = self._worksheet:Range(					-- сделаем из них новый диаппазон
					user_range.Cells(template_row_num, 1),
					user_range.Cells(template_row_num + 1, user_range.Columns.count-1))
			end
		elseif marker == '%$table_rs%$' then
			if row_count > 0 then
				cloneRowCpPs(user_range, template_row_num, row_count+1)
				self._data_range = user_range:Range(
					user_range.Rows(template_row_num+1),
					user_range.Rows(template_row_num+row_count))
			else
				user_range.Rows(template_row_num).EntireRow:Delete()
				self._data_range = nil
			end
		else
			if row_count == 0 then
				user_range.Rows(template_row_num).EntireRow:Delete()
				self._data_range = nil
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
		end

		return self._data_range, user_range, template_values, marker
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
		if self._data_range then
			self._data_range.Rows:AutoFit()
		end
	end,

	SaveAndShow = function(self)
		local run_in_another_process = false
		self._excel.Calculation = self._calc_state
		if(not run_in_another_process) and not TEST_EXCEL_DST_PATH then
			self._excel.visible = true
		end
		self._data_range = nil
		self._workbook:Save()
		self._workbook = nil
		self._worksheet = nil
		collectgarbage("collect")
		if run_in_another_process or TEST_EXCEL_DST_PATH then
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
		local worksheet = self._worksheet
		local c1, c2 = self:ScanTemplateTableRange(worksheet) -- ищем шаблонную таблицу

		local src_table = worksheet:Range(c1, c2)
		if count > 1 then
			local a = worksheet.Cells(c2.row+1, c1.column)
			local dst_range = a:Resize(src_table.Rows.count * (count-1), src_table.Columns.count)
			dst_range:Insert(XlInsertShiftDirection.xlShiftDown)
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
		local data_range, user_range, template_values, marker = self:CloneTemplateRow(dst_row_count, 0, dlgProgress)
		if dst_row_count == 0 then
			return
		end
		if marker == '%$table_rs%$' then
			local row_template = data_range.row - user_range.row
			local col_count = #template_values
			local recordset = generate_recordset_iter(col_count, function (row_num)
				local mark = marks[row_num]
				if mark then
					local row_data = fn_get_templates_data and fn_get_templates_data(mark) or mark
					row_data.N = row_num
					local res_row = apply_values(template_values, {row_data})
					if dlgProgress and
					   row_num % 23 == 1 and
					   not dlgProgress:step(row_num / #marks, sprintf('Сохранение %d / %d', row_num, dst_row_count)) then
							return
					end
					return res_row
				end
			end)
			data_range:CopyFromRecordset(recordset)
			-- восстановим и заполним формулы
			for c = 1, user_range.Columns.count do
				local cell = user_range.Cells(row_template, c)
				-- print(c, cell.Value2)
				if cell.HasFormula then
					local rng = user_range:Range(cell, cell:Offset(#marks, 0))
					rng:FillDown()
				end
			end
			user_range.Rows(row_template):Delete()
		else
			for line = 1, dst_row_count do
				local mark = marks[line]

				local row_data = fn_get_templates_data and fn_get_templates_data(mark) or mark
				row_data.N = line

				local cell_LT = data_range.Cells(line, 1)
				local cell_RB = data_range.Cells(line, data_range.Columns.count)
				local row_range = user_range:Range(cell_LT, cell_RB)

				self:ReplaceTemplates(row_range, {row_data}, template_values)
				if dlgProgress and not dlgProgress:step(line / dst_row_count, sprintf('Сохранение %d / %d', line, dst_row_count)) then
					break
				end
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
			cell.Value2 = tostring(v)

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

if not ATAPE then
	local test_report  = require('local_data_driver')
	local mark_helper = require 'sum_mark_helper'

	local d = test_report.Driver("test_data\\data_27_short.xml")
	local marks = d:GetMarks({ListType="all", GUIDS={"{CBD41D28-9308-4FEC-A330-35EAED9FC802}"}})
	local report_rows = {}
	for _, mark in ipairs(marks) do
		local row = mark_helper.MakeCommonMarkTemplate(mark)
		table.insert(report_rows, row)
	end

	local excel = excel_helper('ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ БЕССТЫКОВОГО ПУТИ.xlsm', 'В6 БП', true)
	excel:ApplyPassportValues(d._passport)
	excel:ApplyRows(report_rows, nil, dlgProgress)
	excel:AppendTemplateSheet(d._passport, report_rows, nil, 3)

	excel:SaveAndShow()
	print('Bye')
end

return excel_helper