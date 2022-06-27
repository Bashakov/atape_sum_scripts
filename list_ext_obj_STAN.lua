local OOP = require 'OOP'
local ext_obj_utils = require 'list_ext_obj_utils'

local function _get_way_param()
	local sql = "SELECT SITEID, NOM, UP_NOM FROM WAY WHERE assetnum = :ASSETNUM"
	local res  = ext_obj_utils.load_objects(sql, {ASSETNUM=Passport.TRACK_CODE}, nil)
	if #res == 1 then
		return res[1].SITEID, res[1].NOM, res[1].UP_NOM
	end
end

local function _load_stan(fnContinueCalc, kms)
	if Passport.TRACK_CODE == '' then
		return {}
	end
	local SITEID, NOM, UP_NOM = _get_way_param()
	if not SITEID then
		return {}
	end

	local sql = [[
		SELECT
		x1.KMIN2 as BEGIN_KM,
		x1.MMIN as BEGIN_M,
		x2.KMAX2 as END_KM,
		x2.MMAX as END_M,
		c.KM as OSKM,
		c.M as OSM,
		x1.ST_KOD as KOD,
		b.NAME

		FROM
		(SELECT u1.KM AS KMIN2,MIN(u1.M) AS MMIN ,u1.ST_KOD FROM
		 (SELECT Min(km) AS KMIN,ST_KOD from STR WHERE SITEID=:SID AND UP_NOM=:NAIM AND PUT_NOM=:PUT group by ST_KOD) t1,STR u1
		   WHERE t1.ST_KOD=u1.ST_KOD AND t1.KMIN=u1.KM AND u1.SITEID=:SID AND u1.UP_NOM=:NAIM AND u1.PUT_NOM=:PUT
						  group by u1.ST_KOD,u1.KM order by u1.KM) x1,

		 (SELECT u2.KM AS KMAX2,MAX(u2.M) AS MMAX ,u2.ST_KOD FROM
		  (SELECT MAX(km) AS KMAX,ST_KOD from STR WHERE SITEID=:SID AND UP_NOM=:NAIM AND PUT_NOM=:PUT group by ST_KOD) t2,STR u2
			WHERE t2.ST_KOD=u2.ST_KOD AND t2.KMAX=u2.KM AND u2.SITEID=:SID AND u2.UP_NOM=:NAIM AND u2.PUT_NOM=:PUT
						  group by u2.ST_KOD,u2.KM order by u2.KM) x2,

		   UP b,STANKM c

		 WHERE
		 x1.ST_KOD=x2.ST_KOD and b.SITEID=:SID AND b.SITEID=c.SITEID
		 and b.UP_NOM=x1.ST_KOD and x1.ST_KOD=c.CODE AND c.UP_NOM=:NAIM

		  ORDER by
		  x1.KMIN2,
		  x1.MMIN
		]]
	return ext_obj_utils.load_objects(sql, {SID=SITEID, NAIM=UP_NOM, PUT=NOM}, function (row)
		return not kms or kms[row.BEGIN_KM] or kms[row.END_KM]
	end)
end

local COL_N =
{
	name = "N",
	align = 'r',
	width = 30,
	get_text = function(row_n, obj)
		return row_n
	end,
}

local function jump(obj, begin)
	local path = begin and {obj.BEGIN_KM, obj.BEGIN_M, 0} or {obj.END_KM, obj.END_M, 0}
	ext_obj_utils.jump_path(path)
end

local COL_NAME =
{
	name = "Название",
	align = 'r',
	width = 120,
	get_text = function(row_n, obj)
		return string.format("%s", obj.NAME)
	end,
}

local COL_CODE =
{
	name = "Код",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return string.format("%s", obj.KOD)
	end,
}

local COL_PATH_START =
{
	name = "Начало",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.BEGIN_KM, obj.BEGIN_M)
	end,
	on_dbl_click = function(row_n, obj)
		jump(obj, true)
	end,
	get_color = function(row_n, obj)
        return {0x000000, 0xfffff0}
    end
}

local COL_PATH_END =
{
	name = "Конец",
	align = 'r',
	width = 60,
	get_text = function(row_n, obj)
		return string.format("%d.%03d", obj.END_KM, obj.END_M)
	end,
	on_dbl_click = function(row_n, obj)
		jump(obj, false)
	end,
	get_color = function(row_n, obj)
        return {0x000000, 0xf0fff0}
    end
}

local STAN = OOP.class
{
	name = "Станции",
	columns =
	{
		COL_N,
		COL_NAME,
		COL_CODE,
		COL_PATH_START,
		COL_PATH_END,
	},
	ctor = function (self, fnContinueCalc)
		local kms = ext_obj_utils.get_data_kms(fnContinueCalc)
		self.objects = _load_stan(fnContinueCalc, kms)
		return #self.objects
	end,
	get_object = function (self, row)
		return self.objects[row]
	end,
	OnMouse = function(self, act, flags, cell, pos_client, pos_screen)
        local object = self:get_object(cell.row)
		local column = self.columns[cell.col]
        if act == 'left_dbl_click' and object then
			if column and column.on_dbl_click then
				column.on_dbl_click(cell.row, object)
			end
        end
    end,
	GetExtObjMarks = function (self)
		local res = {}
		for i, obj in ipairs(self.objects) do
			local name = string.format("%s", obj.NAME)
			for begin = 0, 1 do
				local id = i*2+begin
				local description = begin==0 and "Начало " or "Конец "
				local path = begin==0 and {obj.BEGIN_KM, obj.BEGIN_M, 0} or {obj.END_KM, obj.END_M, 0}
				res[id] = {
					path = path,
					description = description .. name,
					vert_line = 1,
					icon_file = 'Images/SUM.bmp',
					icon_rect = {(begin==0 and 6 or 7) * 16, 32, 16, 16},
					id = id,
				}
			end
		end
		return res
	end,
}

return
{
    filters = {
        STAN,
    }
}
