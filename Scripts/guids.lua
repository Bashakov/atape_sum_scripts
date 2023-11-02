local function swap(a)
    assert(type(a) == 'table' and #a == 16)
    local res = {
        a[4], a[3], a[2], a[1],
        a[6], a[5],
        a[8], a[7],
        a[9], a[10],
        a[11], a[12], a[13], a[14], a[15], a[16],
    }
    return res
end

local function hex2array(h, le)
    assert(type(h) == 'string' and string.len(h) == 32)
    local a = {}
    for i = 1, 32, 2 do
        local hh = h:sub(i, i+1)
        table.insert(a, tonumber(hh, 16))
    end
    assert(#a == 16)
    if le then a = swap(a) end
    return a
end

local function bin2array(b, le)
    assert(type(b) == 'string' and string.len(b) == 16)
    local a = {string.byte(b, 1, 16)}
    if le then a = swap(a) end
    return a
end

local function array2str(a)
    assert(type(a) == 'table' and #a == 16)
    local guid_fmt = '{%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X}'
    local s = string.format(guid_fmt, table.unpack(a))
    return s
end

local function str2array(s)
    assert(type(s) == 'string')
    s = s:gsub("[{}-]", "")
    assert(s:len() == 32)
    local a = hex2array(s)
    return a
end

local function hex2str(h, le)
    return array2str(hex2array(h, le))
end

local function bin2str(h, le)
    return array2str(bin2array(h, le))
end

-- =============== TEST ================== --

if not pcall(debug.getlocal, 4, 1) then
    print("TEST GUIDS")
    local ref_str = "{11223344-5566-7788-9900-AABBCCDDEEFF}"
    local ref_bin_le = "\x44\x33\x22\x11\x66\x55\x88\x77\x99\x00\xAA\xBB\xCC\xDD\xEE\xFF"
    local ref_bin_be = "\x11\x22\x33\x44\x55\x66\x77\x88\x99\x00\xAA\xBB\xCC\xDD\xEE\xFF"
    local ref_hex_le = "44332211665588779900AABBCCDDEEFF"
    local ref_hex_be = "11223344556677889900AABBCCDDEEFF"

    assert(ref_str == bin2str(ref_bin_be, false))
    assert(ref_str == bin2str(ref_bin_le, true))
    assert(ref_str == hex2str(ref_hex_be, false))
    assert(ref_str == hex2str(ref_hex_le, true))
    assert(ref_str == array2str(str2array(ref_str)))

    print("OK")
end

-- ============= EXPORT =================== --

return {
    hex2array = hex2array,
    bin2array = bin2array,
    array2str = array2str,
    str2array = str2array,
    hex2str = hex2str,
    bin2str = bin2str,
}
