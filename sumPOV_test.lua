local sumPOV = require "sumPOV"

local function flags2str(mark)
	local names = {"POV_OPERATOR", "POV_EAKSUI", "POV_REPORT", "POV_REJECTED" }
	local res = ''
	for i, name in ipairs(names) do
		res = res  .. (mark.ext[name] or '.')
	end
	return res
end

local function make_test_mark(str_flags)
	local names = {"POV_OPERATOR", "POV_EAKSUI", "POV_REPORT", "POV_REJECTED" }
	local ff = {string.match(str_flags, "^(.)(.)(.)(.)$")}
	if #ff ~= #names then error(string.format('flags MUST by string from %d chars', #names)) end
	local mark = {
		prop = {Description = str_flags},
		ext = {} }
	for i, name in ipairs(names) do if tonumber(ff[i]) then mark.ext[name] = tonumber(ff[i]) end end 
	return mark
end

local function make_test_marks()
	local names = {"POV_OPERATOR", "POV_EAKSUI", "POV_REPORT", "POV_REJECTED"}
	local res = {}
	for op = -1,1 do for ek = -1,2 do for rp = -1,1 do for rj = -1,1 do
		local mark = { prop = {}, ext = {} }
		for i, name in ipairs(names) do
			local val = select(i, op, ek, rp, rj)
			if val >= 0 then mark.ext[name] = val end
		end
		mark.prop.Description = flags2str(mark)
		table.insert(res, mark)
	end end end end
	return res
end

-- =========================== TESTS =============================

-- проверка генерации описания сценария
if 1 == 0 then
	sumPOV.ShowSettings()
	print(sumPOV.GetCurrentSettingsDescription())
end

-- проверка генерации описания отметки
if 1 == 0 then
	local test_marks = make_test_marks()
	for _, mark in ipairs(test_marks) do
		print(mark.prop.Description, '->', sumPOV.GetMarkDescription(mark))
	end
end

-- проверка подтверждения отметки
if 1 == 0 then
	sumPOV.ShowSettings()
	local mark = make_test_mark('1.0.')
	print('before:', sumPOV.GetMarkDescription(mark))
	sumPOV.UpdateMarks(mark)
	print('after: ', sumPOV.GetMarkDescription(mark))
end

-- проверка редактирования отметки 
if 1 == 0 then
	local mark = make_test_mark('1.0.')
	print('before:', sumPOV.GetMarkDescription(mark))
	sumPOV.EditMarks(mark)
	print('after: ', sumPOV.GetMarkDescription(mark))
end

-- проверка фильтрации отметок
if 1 == 0 then
	local mark = make_test_mark('.1.0')
	
	local filter_ekasui = MakeReportFilter(true)
	if filter_ekasui then
		print(filter_ekasui(mark))
	end
	
	local filter_vedomost = MakeReportFilter(false)
	if filter_vedomost then
		print(filter_vedomost(mark))
	end
end


-- проверка фильтрации отметок
if 1 == 1 then
	local test_marks = make_test_marks()
	local res = {}
	for _, ekasui in ipairs{true, false} do
		local r = {}
		local filter = MakeReportFilter(ekasui)
		if filter then
			for i, mark in ipairs(test_marks) do
				r[i] = filter(mark)
			end
		end
		res[ekasui] = r
	end
	
	print('N   | ekasui | vedom | flags | desc')
	for i, mark in ipairs(test_marks) do
		print(i, res[true][i], res[false][i], mark.prop.Description, sumPOV.GetMarkDescription(mark))
	end
end
