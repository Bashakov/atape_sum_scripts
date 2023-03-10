-- https://bt.abisoft.spb.ru/view.php?id=932
-- https://bt.abisoft.spb.ru/view.php?id=1006


-- используется строка, а не sum_types, тк будет проблема загрузкой sum_process.lua
local GUIDS =
{
	"{29FF08BB-C344-495B-82ED-00000000000C}", -- Дефектоподобн.пачка в зоне болт.стыка  -- TYPES.OTMETKA_12,
	"{29FF08BB-C344-495B-82ED-000000000010}", -- Дефектоподобн.пачка в Ч/Р              -- TYPES.OTMETKA_16,
}


local LEVEL =
{
	HI      = 1,
	MED     = 2,
	LO      = 3,
	NONE    = 4,
}

local POSITION =
{
    NECK = 1,
    HEAD = 2,
}

local function get_recog_params(mark)
	local desc = mark.Description or mark.prop.Description  -- отметка из sum_process.lua или нового типа
    if type(desc) == "string" then
        local IP, CN, G = string.match(desc, "IP:%s*(%d+)%s*CN:%s*(%d+)%s*G:%s*(%d+)")
	    return tonumber(IP), tonumber(CN), tonumber(G)
    end
end

local function get_lvl(mark)
    local IP, CN, G = get_recog_params(mark)
    if IP then
        if        1 <= IP and IP <=  200    then   return  LEVEL.NONE
        elseif  201 <= IP and IP <=  400    then   return  LEVEL.LO
        elseif  401 <= IP and IP <= 1400    then   return  LEVEL.MED
        elseif 1401 <= IP                   then   return  LEVEL.HI
        end
    end
end





local function enum_channel(mark)
    local mask = mark.ChannelMask or mark.prop.ChannelMask
	local num = 0
	return coroutine.wrap(function()
		while mask > 0 do
			if bit32.btest(mask, 1) then
				coroutine.yield(num)
			end
			num = num + 1
			mask = bit32.rshift(mask, 1)
		end
	end)
end

local function _load_channel_types()
    local res = {}
    for _, ch in ipairs(Passport.CHANNELS) do
        local n = tonumber(ch.NUM)
        local a = tonumber(ch.ALPHA)
        if n and a then
            a = math.abs(a)
            if a <= 50 then
                res[n] = POSITION.NECK
            elseif a > 50 then
                res[n] = POSITION.HEAD
            end
        end
    end
    return res
end

local CHANNEL_TYPES

local function check_position(mark, pos)
    if not CHANNEL_TYPES then
        CHANNEL_TYPES = _load_channel_types()
    end

    for num in enum_channel(mark) do
        if CHANNEL_TYPES[num] == pos then
            return true
        end
    end
    return false
end



local function _load_channel_names()
    local res = {}
    for _, ch in ipairs(Passport.CHANNELS) do
        local n = tonumber(ch.NUM)
        if n then
            res[n] = ch.NAME
        end
    end
    return res
end

local CHANNEL_NAMES

local function get_channels_str(mark)
    if not CHANNEL_NAMES then
        CHANNEL_NAMES = _load_channel_names()
    end
    local res = {}
    for num in enum_channel(mark) do
        local name = CHANNEL_NAMES[num]
        if name then
            table.insert(res, name)
        end
    end
    return table.concat(res, ", ")
end

-- =======================================================

return
{
    LEVEL = LEVEL,
    GUIDS = GUIDS,
    POSITION = POSITION,
    get_lvl = get_lvl,
    get_recog_params = get_recog_params,
    check_position = check_position,
    get_channels_str = get_channels_str,
}
