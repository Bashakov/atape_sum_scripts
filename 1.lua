print(os.date("%d.%m.%Y %H:%M:%S"))





local function get_user_options(mark)
	local text = mark.ext.DEFECT_OPTIONS
	local res = {}
	string.gsub(text or '', '([^\n]+)', function(s)
			local n,v = string.match(s, '([^:]+):(.*)')
			print(s, n, v)
			if n then
				res[n] = v
			end
		end)
	return res
end

local m = {ext={DEFECT_OPTIONS='val = 123\nconnector_count:\nconnector_placmaent:\nconnector_type:ДО'}}
get_user_options(m)

a = {[1]=2, r=30, [2]=3}
print(table.unpack(a))