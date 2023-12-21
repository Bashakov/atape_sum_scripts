
local function _split_line(line, sep)
	local fieldstart = 1
	local res = {}
	local len = string.len(line)
	repeat
		local nexti = string.find(line, sep, fieldstart) or len+1
		table.insert(res, string.sub(line, fieldstart, nexti-1))
		fieldstart = nexti + 1
	until fieldstart > len
	return res
end

local function _make_object(row, header)
	local res = {}
	for i = 1,#header do
		res[header[i]] = row[i]
	end
	return res
end

local function iter_csv(file_path, sep, has_header)
	if not sep then sep = ';' end

	local header = nil
	local num = 0
	return coroutine.wrap(function()
		for	line in io.lines(file_path) do
			num = num + 1
			if line and string.sub(line, 1, 1) ~= '#' then
				local row = _split_line(line, sep)
				if has_header and not header then
					header = row
					has_header = false
				else
					if header then
						row = _make_object(row, header)
					end
					--print(row)
					coroutine.yield(num, row)
				end
			end
		end
	end)
end


return {
	iter_csv = iter_csv
}