-- скрипт управления параметрами отображением ММ данных

-- ================================================================


local value_range = {0, 0}


-- ================= Экспортируемые функции =======================

--[[
	функция вызывается при открытии данных (для каждого режима отображения ММ).
	В данной функции можно установить необходимые глобальные переменные.
	
	Функция приниммает 3 параметра: 
		- название схемы прозвучивания ("03Ex-22", "device_70" ...), 
		- режим лента/шифровка (true, flase), 
		- режим отображения ('mean', 'cscan', 'plots').
	
	Функция должна вернуть массив с 2 значениями - диаппазон регулировок, 
	он будет применен к рулеру на диалоге настроек отображения.
]]
function Init(device_name, registration, show_mode)
	print('Init', device_name, registration, show_mode)
	
	value_range = {10, 10000}
	
	if show_mode == 'mean' or show_mode == 'plots' then
		value_range = {30, 3000}
	elseif show_mode == 'cscan' then
		value_range = {30, 3000}
	end
	return value_range
end


--[[ 
	Функция вызвается для определения текста, который будет отображен на панели усилений.
	Функция принимает один параметр, значение диапазона
	Функция должна вернуть строку
]]
function GetText(value)
	value = math.max(value, 1)
	value = value_range[2] / value
	value = math.max(value, 1)
	value = 10.0 * math.log10(value)
	return string.format('%.1f', value)
end


--[[
	Функция вызывается при скроле мыши над областью ММК на панели усилений
	Функция принимает 4 параметра:
		- текущее значение диаппазона,
		- step = количество шагов,
		- ctrl = нажата кн. ctrl
		- shift = нажата кн. shift
	Функция должна вернуть новое значение диапазона.
]]
function OnMouseWheel(cur_value, step, ctrl, shift)
	print('OnMouseWheel', cur_value, step, ctrl, shift)
	step = -step

	if ctrl then
		step = step * 1
	elseif shift then
		step = step * 100
	else
		step = step * 10
	end
	local value = cur_value + step
	value = math.max(value, value_range[1])
	value = math.min(value, value_range[2])
	return value
end


-- ================================== ТЕСТ =================================== 

if not ATAPE then
	local r = Init("common", false, "mean")
	print(r[1], r[2])
	
	for _, v in ipairs{0, 1, 3, 10, 30, 100, 300, 1000} do
		print(v, GetText(v))
	end
end
