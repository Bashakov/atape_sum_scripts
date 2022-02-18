
local ErrorUserAborted =
{
	cause='UserAborted',
}

ErrorUserAborted.skip = function(fn, ...)
	local res = {pcall(fn, ...)}
	local status = res[1]
	table.remove(res, 1)
	if status then
		return table.unpack(res)
	end
	if res[1] ~= ErrorUserAborted then
		error(res[1])
	end
end


setmetatable(ErrorUserAborted, {
	__call = function ()
		error(ErrorUserAborted)
	end
})

return ErrorUserAborted
