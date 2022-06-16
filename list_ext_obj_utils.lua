if iup then
	iup.SetGlobal('UTF8MODE', 1)
end


local function get_data_kms(fnContinueCalc)
	local sys_begin, sys_end = Driver:GetSysCoordRange()
    if not sys_begin then
        iup.Message("ATape", "отсутсвует функция Driver:GetSysCoordRange, требуется обновление ATape")
        return
    end
	sys_end = sys_end + 1
	local step = (sys_end - sys_begin) / 1000
	step = math.max(step, 30000)
	step = math.min(step, 300000)
	local kms = {}
	local c = sys_begin
	while c < sys_end do
		local km, _, _ = Driver:GetPathCoord(c)
		kms[km-1] = true
		kms[km] = true
		kms[km+1] = true
		if fnContinueCalc and not fnContinueCalc((c-sys_begin) / (sys_end-sys_begin)) then
			return {}
		end
		c = c + step
	end
	return kms
end

local function jump_path(km, m)
	if not Driver:JumpPath({km, m, 0}) then
		local msg = string.format("Не удалось перейти на координату %d km %d m", km, m)
		iup.Message("ATape", msg)
	end
end

return 
{
    get_data_kms = get_data_kms,
	jump_path = jump_path,
}
