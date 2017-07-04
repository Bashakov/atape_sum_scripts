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
				stuff.save(fname, v, saved)
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
	return string.format(s, ...)
end

function stuff.errorf(s,...)        
	error(string.format(s, ...))
end

local escape_hlper = function(c) 
	return string.format('\\x%02X', string.byte(c))
end

function stuff.escape(s, ptrn)
	ptrn = ptrn or '[%c%s]'
	local res = string.gsub(s, ptrn, escape_hlper)
	return res
end

function stuff.GetUtcOffset()
	local ts = 86000 * 5
	local cur, utc = os.date("*t", ts), os.date("!*t", ts)
	local diff = (cur.day - utc.day) * 24 + (cur.hour - utc.hour)
	return diff
end

local function make_sleeper()
	-- for n,v in pairs(os) do print(n, v) end
	if os.sleep then
		return os.sleep
	end
	
	
	local ok, socket = pcall(require, "socket")
	if ok then 
		return function(sec)
			socket.select(nil, nil, sec)
		end
	end
	error("This version of interpretator without SLEEP function!!!")
--		local clock = os.clock
--		return function(sec)  -- seconds
--			local t0 = clock()
--			while clock() - t0 <= sec do end
--		end
--	end
end

local sleeper = make_sleeper()

function stuff.sleep(sec)
	sleeper(sec)
end

function stuff.is_file_exists(name)
   local f = io.open(name, "r")
   if f then 
	   io.close(f) 
	   return true 
	else 
		return false 
	end
end



return stuff