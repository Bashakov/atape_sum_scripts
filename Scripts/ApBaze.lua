local sqlite3 = require "lsqlite3"
local utils = require "utils"
local OOP = require "OOP"
local alg = require "algorithm"


local function get_db_path()
	local path = EKASUI_PARAMS.ApBAZE or "D:/ATapeXP/Tools/GBPD/ApBAZE.db"
	return path
end

local function open_db()
	local path = get_db_path()
	if not utils.is_file_exists(path) then
		local msg = string.format("file [%s] not exist", path)
		error(msg)
	end

	local flags = sqlite3.SQLITE_OPEN_READONLY
	local db = assert(sqlite3.open(path, flags))
	return db
end

local function load_objects(sql, bind_values, filter_row)
	local db = open_db()
	local stmt = db:prepare(sql)
	if not stmt then
		local msg = string.format('%s(%s) on %s', db:errcode(), db:errmsg(), sql)
		error(msg)
	end
	stmt:bind_names(bind_values)
	local res = {}
	for row in stmt:nrows() do
		if not filter_row or filter_row(row) then
			table.insert(res, row)
		end
	end
	db:close()
	return res
end

local velocityTable = OOP.class{
    loadPsp = function (self, psp)
        self:load(psp.TRACK_CODE, psp.SITEID)
    end,

    load = function (self, assetnum, siteid)
        local sql = [[
            SELECT
                v.BEGIN_KM, v.BEGIN_M, v.END_KM, v.END_M, v.VPASS, v.VGR, v.VSAPS, v.VLAST
            FROM
                VUS as v 
            JOIN
                WAY as w ON	v.UP_NOM = w.UP_NOM and v.PUT_NOM = w.NOM and v.SITEID = w.SITEID
            WHERE
                w.ASSETNUM = :ASSETNUM and v.SITEID = :SITEID
        ]]
        self._items = load_objects(sql, {ASSETNUM=assetnum, SITEID=siteid or EKASUI_PARAMS.SITEID})
        for _, item in ipairs(self._items) do
            local bm = item.BEGIN_M
            if bm == 1 then bm = 0  end
            item.RANGE = {
                self._prep_path(item.BEGIN_KM, bm),
                self._prep_path(item.END_KM,   item.END_M)}
        end
        table.sort(self._items, function (a, b)
            return a.RANGE[1] < b.RANGE[1]
        end)
    end,

    format = function (self, km, m)
        return self.format_item(self:find(km, m))
    end,

    find = function (self, km, m)
        local req_path = self._prep_path(km, m)
        local search_item = {RANGE = {req_path,req_path}}
        local pred = function (a, b) return a.RANGE[2] < b.RANGE[2] end
        local i = alg.lower_bound(self._items, search_item, pred)
        if i <= #self._items then
            local item = self._items[i]
            if item.RANGE[1] <= req_path and req_path <= item.RANGE[2] then
                return item
            end
        end
    end,

    format_item = function (item)
        if not item then
            return ''
        end
        local res = {}
        if item.VSAPS ~= 0 then
            table.insert(res, string.format("сапс %d", item.VSAPS))
        end
        if item.VLAST ~= 0 then
            table.insert(res, string.format("лст %d", item.VLAST))
        end
        table.insert(res, string.format("%d/%d", item.VPASS, item.VGR))
        return table.concat(res, '/')
    end,

    _prep_path = function (km, m)
        return km * 10000 + m
    end,
}


return {
    open_db = open_db,
    load_objects = load_objects,
    VelocityTable = velocityTable,
}
