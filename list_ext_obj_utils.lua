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
	-- local res = {}
	-- for km in pairs(kms) do table.insert(res, km) end
	-- table.sort(res)
	return kms
end

return {
    get_data_kms = get_data_kms
}
