local base = _G
local module = module

module('ExtGpsWriter')

function rebase_global()
	local global_names = {'assert', 'io', 'ipairs', 'pairs', 'string', 'setmetatable', 'print', 'require', 'type', 'error', 'table'}
	for _,n in base.pairs(global_names) do 
		_M[n] = base[n] 
	end
end
rebase_global()

local sqlite3 = require("lsqlite3")


printf  = function(s,...)        return base.io.write(s:format(...)) 		end
sprintf = function(s,...)        return s:format(...)						end

dump = function (o) 
	if base.type(o) == "number" then
		io.write(o)
	elseif base.type(o) == "string" then
		io.write(string.format("%q", o))
	elseif base.type(o) == "table" then
		io.write("{\n")
		for k,v in base.pairs(o) do
			io.write(" ", k, " = ")
			dump(v)
			io.write(",\n")
		end
		io.write("}\n")
	else
		base.error("cannot dump a " .. base.type(o))
	end
end


-- ============================================================ 

data_base = {}

function data_base:open(data_path)
	 self.engine = sqlite3.open(data_path)
end

function data_base:exec(query, ...)
	base.assert(self.engine)
	local stmt = self.engine:prepare(query)
	self:assert(stmt)
	
	stmt:bind_values(...)
	stmt:step()
	stmt:finalize()
end

function data_base:transaction(arg)
	self:exec("BEGIN TRANSACTION")
	local ok, msg = base.pcall(arg.body_fn)
	if ok then
		self:exec("COMMIT")
	else
		self:exec("ROLLBACK")
		print("error: " .. msg)
	end
end

function data_base:assert(test, msg, ...)
	if not test then 
		local ures_msg = msg and base.string.format(msg.."\n", ...) or ""
		local db_error = "Sqlite ERROR: " .. self.engine:errmsg()
		error(ures_msg .. db_error)
	end
end

function data_base:msg(test, msg, ...)
	if not test then 
		local ures_msg = msg and base.string.format(msg.."\n", ...) or ""
		local db_error = "Sqlite ERROR: " .. self.engine:errmsg()
		print(ures_msg .. db_error)
	end
end

-- ============================================================ 

ExtGpsDB = {}

function ExtGpsDB:_open(passport_path)
	base.assert(passport_path, 'empty passport path')
	local db_path = passport_path .. '.egps'
	self.db = data_base
	self.db:open(db_path)
end

function ExtGpsDB:_check_tables(req_version)
	base.assert(self.db, 'not opened')
	
	self.db:exec("CREATE TABLE IF NOT EXISTS version (version INTEGER);")
	local f, v = self.db.engine:rows("SELECT max(version) FROM version")
	local ver = f(v)
	if not ver[1] or ver[1] < req_version then
		self.db:exec("INSERT INTO version VALUES (?);", req_version)
		
		self.db:exec[[ CREATE TABLE coordinates (
				sys_coord   INTEGER PRIMARY KEY,
				latitude	REAL,
				longitude	REAL,
				altitude	REAL,
				utc			INTEGER,
				quality		INTEGER
			);]]
		self.db:exec[[ CREATE TABLE raw_data (
				sys_coord   INTEGER PRIMARY KEY, 
				pps			INTEGER,
				data		TEXT,
				FOREIGN KEY	(sys_coord) REFERENCES coordinates(sys_coord)
			);]]
		self.db:exec[[ CREATE TABLE info_types (
				type		INTEGER PRIMARY KEY AUTOINCREMENT, 
				name		TEXT,
				UNIQUE		(name)
			);]]
		self.db:exec[[ CREATE TABLE info (
				id 			INTEGER PRIMARY KEY,
				sys_coord	INTEGER,
				type		INTEGER,
				value		REAL,
				FOREIGN KEY	(sys_coord) REFERENCES coordinates(sys_coord),
				FOREIGN KEY	(type) 		REFERENCES info_types(type),
				UNIQUE 		(sys_coord, type)
			);]]
	end
	
	self.types = {}
end

function ExtGpsDB:_fetch_types(new_type)
	assert( new_type or (self.types[new_type] == nil) )
	assert(self.db)
	if new_type then 
		self.db:exec('INSERT INTO info_types(name) VALUES (?)', new_type)
	end
	
	self.types = {}
	for tp, name in self.db.engine:urows('SELECT type, name FROM info_types') do
		self.types[name] = tp
	end
	return self.types
end	

function ExtGpsDB:_make_inserters()
	self.stmt_coord_inserter = self.db.engine:prepare[[
		INSERT INTO 
			coordinates(sys_coord, latitude, longitude, altitude, utc, quality) 
		VALUES (:sc, :lat, :lon, :alt, :utc, :q)]]
	self.db:assert(self.stmt_coord_inserter, "make stmt_coord_inserter")
	
	self.stmt_info_inserter = self.db.engine:prepare[[
		INSERT INTO 
			info(sys_coord, type, value) 
		VALUES (:sc, :tp, :val)]]
	self.db:assert(self.stmt_info_inserter, "make stmt_info_inserter")
	
	self.stmt_rawgps_inserter = self.db.engine:prepare[[
		INSERT INTO 
			raw_data(sys_coord, pps, data) 
		VALUES (:sc, :pps, :raw)]]
	self.db:assert(self.stmt_rawgps_inserter, "make stmt_rawgps_inserter")
end


function ExtGpsDB:_insert_coord(sc, lat, lon, alt, utc, qul)
	assert(sc and lat and lon and alt and utc and qul)
	local stmt = self.stmt_coord_inserter
	assert(stmt)
	stmt:bind_names{ sc=sc, lat=lat, lon=lon, utc=utc, q=qul}
	local res = stmt:step()
	self.db:msg(res == sqlite3.DONE, "stmt_coord_inserter failed")
	stmt:reset()
end

function ExtGpsDB:_insert_info(sc, name, value)
	assert(sc and name and value)
	local stmt = self.stmt_info_inserter
	assert(stmt)
	assert(self.types)
	
	if not self.types[name]	then	self:_fetch_types(name)	end
	local tp = self.types[name]
	assert(tp)
	
	stmt:bind_names{ sc=sc, tp=tp, val=value}
	local res = stmt:step()
	self.db:msg(res == sqlite3.DONE, "stmt_info_inserter failed")
	stmt:reset()
end

function ExtGpsDB:_insert_raw(sc, pps, gps)
	assert(sc and pps and gps)
	local stmt = self.stmt_rawgps_inserter
	assert(stmt)
	stmt:bind_names{ sc=sc, pps=pps, raw=gps}
	local res = stmt:step()
	self.db:msg(res == sqlite3.DONE, "stmt_rawgps_inserter failed")
	stmt:reset()
end


-- ----------------------------------------------------------------- --

function OpenEGps(passport_path)
	local egps = {}
	base.setmetatable(egps, {__index=ExtGpsDB})
	egps:_open(passport_path)
	egps:_check_tables(101)
	egps:_make_inserters()
	egps:_fetch_types()
	return egps
end

function ExtGpsDB:on_data(sc, pps, parsed, gps)
	local coord_data = {'Latitude', 'Longitude', 'Altitude', 'UTC', 'Quality'}
	local coord = {sc}
	for _, n in ipairs(coord_data) do
		local d = parsed[n] or 0
		table.insert(coord, d)
		parsed[n] = nil
	end
	self:_insert_coord(table.unpack(coord))
	
	for n, v in pairs(parsed) do
		self:_insert_info(sc, n, v)
	end
	
	self:_insert_raw(sc, pps, gps)
end

-- ================================================================= --

function test()
	local egps = OpenEGps('test')
	
	local cc = 10000
	local x = base.os.clock()
	egps.db:transaction{body_fn = function()
		for i = 1, cc do
			egps:InsertCoords(i, i, i + .01, i + 2.02, i)
		end
	end }
	local eps = (base.os.clock() - x)

	printf( "insert %d rec in %f sec (%.1f usec/rec)\n", cc, eps, eps * 1000000.0 / cc) 
end 

function test2()
	local td = {
		{gps = "$GPGGA,094520.590,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4c",
		parsed = {
			UTC = 35120590,
			Latitude = 37.391097950667,
			Longitude = 122.03782631066667,
			Quality = 2,
			NOS	= 6,
			HDOP = 1.2,
			Altitude = 18893.0,
			GeoidSep = -25669,
			AgeDiff	= 2.0,
			DiffStID = 31 }}, 
		{gps = "$GPGGA,094520.590,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4c",
		parsed = {
			UTC = 35120591,
			Latitude = 38.391097950667,
			Longitude = 123.03782631066667,
			Quality = 4,
			NOS	= 8,
			HDOP = 1.5,
			Altitude = 18893.1,
			GeoidSep = -25670,
			AgeDiff	= 2.1,
			DiffStID = 32 }},
	}
	
	local egps = OpenEGps('test_1')	
	for i, d in ipairs(td) do
		egps:on_data(i, i, d.parsed, d.gps)
	end
end

--test2()