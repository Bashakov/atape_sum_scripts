local stuff = {}

local function basicSerialize (o)
	if type(o) == "number" then
		return tostring(o)
	else -- assume it is a string
		return string.format("%q", o)
	end
end
	
function stuff.save (name, value, saved)
	saved = saved or {} -- initial value
	io.write(name, " = ")
	if type(value) == "number" or type(value) == "string" then
		io.write(basicSerialize(value), "\n")
	elseif ({['function']=1, ['userdata']=1})[type(value)] then
		io.write(type(value), "\n")		
	elseif type(value) == "table" then
		if saved[value] then -- value already saved?
			io.write(saved[value], "\n") -- use its previous name
		else
			saved[value] = name -- save name for next time
			io.write("{}\n") -- create a new table
			for k,v in pairs(value) do -- save its fields
				k = basicSerialize(k)
				local fname = string.format("%s[%s]", name, k)
				save(fname, v, saved)
			end
		end
	else
		error("cannot save a " .. type(value))
	end
end

function stuff.printf (s,...)    
	return io.write(s:format(...))		
end

function stuff.sprintf(s,...)        
	return s:format(...)                  		
end

function stuff.GetUtcOffset()
	local ts = 86000 * 5
	local cur, utc = os.date("*t", ts), os.date("!*t", ts)
	local diff = (cur.day - utc.day) * 24 + (cur.hour - utc.hour)
	return diff
end

return stuff