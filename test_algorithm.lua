local lu = require("luaunit")

local algorithm = require 'algorithm'

function TestList()
    local gen = function(n)
        return function ()
            if n > 0 then
                n = n - 1
                return n
            end
        end
    end

    local g = gen(4)
    local actual = algorithm.list(g)
    lu.assertEquals(actual, {3, 2, 1, 0})
end

function TestMap()
    local src = {1,2,3}
    local actual = algorithm.map(function (x)
        return x*2
    end, src);
    lu.assertEquals(actual, {2, 4, 6})
end

function TestFilter()
    local src = {1,2,3,4,5}
    local actual = algorithm.filter(function (x)
        return x % 2 == 0
    end, src);
    lu.assertEquals(actual, {2, 4})
end

function TestZip()
    local src1 = {1, 2, 3}
    local src2 = {'a', 'b', 'c'}

    local actual = algorithm.zip(src1, src2)
    lu.assertEquals(actual, {{1, 'a'}, {2, 'b'}, {3, 'c'}})
end

function TestIZip()
    local src1 = {1, 2, 3}
    local src2 = {'a', 'b', 'c'}

    local actual = {}
    for a, b, c in algorithm.izip(src1, src2) do
        lu.assertIsNil(c)
        table.insert(actual, {a, b})
    end
    lu.assertEquals(actual, {{1, 'a'}, {2, 'b'}, {3, 'c'}})
end

function TestSort()
    local src = {1, -2, 3, 4, -5}
    lu.assertEquals(algorithm.sort(src), {-5, -2, 1, 3, 4})
    lu.assertEquals(algorithm.sort(src, None, false), {4, 3, 1, -2, -5})
    lu.assertEquals(algorithm.sort(src, function (x) return math.abs(x) end), {1, -2, 3, 4, -5})
    lu.assertEquals(algorithm.sort(src, function (x) return math.abs(x) end, false), {-5, 4, 3, -2, 1})
    lu.assertEquals(algorithm.sort(src, function (x) 
        return -(x > 0 and 1 or -1), math.abs(x)
    end), {1, 3, 4, -2, -5})
end

function TestSorted()
    local res = {}
    for n, v in algorithm.sorted{a=1, c=3, b=2} do
        table.insert(res, {n, v})
    end
    lu.assertEquals(res, {{'a', 1}, {'b', 2}, {'c', 3}})
    
end

function TestEnumGroup()
    local res = {}
    for a,b,c in algorithm.enum_group({1,2,3,4,5}, 3) do
        table.insert(res, {a,b,c})
    end
    lu.assertEquals(res, {{1,2,3}, {2,3,4}, {3,4,5}})
end

function TestSplitChunksIter()
    local res = {}
    for n, g in algorithm.split_chunks_iter(3, {1,2,3,4,5,6,7}) do
        table.insert(res, {n, g})
    end
    lu.assertEquals(res, {{1, {1,2,3}}, {2, {4,5,6}}, {3, {7}}})
end

function TestSplitChunks()
    lu.assertEquals(
        algorithm.split_chunks(3, {1,2,3,4,5,6,7}),
        {{1,2,3}, {4,5,6}, {7}})
end

function TestTableFind()
    local src = {10, 30, 20}
    lu.assertIsNil(algorithm.table_find(src, 0))
    lu.assertEquals(algorithm.table_find(src, 10), 1)
    lu.assertEquals(algorithm.table_find(src, 20), 3)
    lu.assertEquals(algorithm.table_find(src, 30), 2)
    lu.assertIsNil(algorithm.table_find(src, 40))
end

function TestTableMerge()
    lu.assertEquals(algorithm.table_merge(1, 'a', {1,2}, "q"), {1, 'a', 1, 2, "q"})
end

function TestReverseArray()
    local a = {}
    algorithm.reverse_array(a)
    lu.assertEquals(a, {})

    table.insert(a, 1)
    algorithm.reverse_array(a)
    lu.assertEquals(a, {1})

    table.insert(a, 2)
    algorithm.reverse_array(a)
    lu.assertEquals(a, {2, 1})

    table.insert(a, 3)
    algorithm.reverse_array(a)
    lu.assertEquals(a, {3, 1, 2})
end

function TestEqualRange1()
    local src = {10, -20, 30, 40, -50}
    local pred = function (a, b) return math.abs(a) < math.abs(b) end
    local er = function (x) return {algorithm.equal_range(src, x, pred)} end
    lu.assertEquals(er( 5), {1, 1})
    lu.assertEquals(er(10), {1, 2})
    lu.assertEquals(er(15), {2, 2})
    lu.assertEquals(er(20), {2, 3})
    lu.assertEquals(er(45), {5, 5})
    lu.assertEquals(er(50), {5, 6})
    lu.assertEquals(er(55), {6, 6})
end

function TestEqualRange2()
    local er = function(a, v, p) local l, b = algorithm.equal_range(a, v, p) return {l, b} end

    local a = {10,20,}

    lu.assertEquals({1, 1}, er(a, 5))
    lu.assertEquals({1, 2}, er(a, 10))
    lu.assertEquals({2, 2}, er(a, 15))
    lu.assertEquals({2, 3}, er(a, 20))
    lu.assertEquals({3, 3}, er(a, 25))

    lu.assertEquals({1, 1}, er({}, 0))

    local l = {}
    for i = 1,1000 do l[i] = i end
    for i,_ in ipairs(l) do
        lu.assertEquals({i, i+1}, er(l, i))
    end
end

function TestStartsWith()
    lu.assertIsTrue(algorithm.starts_with("", ""))
    lu.assertIsTrue(algorithm.starts_with("12", "12"))
    lu.assertIsTrue(algorithm.starts_with("123", "12"))
    lu.assertIsTrue(algorithm.starts_with("1", ""))
    lu.assertIsFalse(algorithm.starts_with("", "1"))
    lu.assertIsFalse(algorithm.starts_with("12", "123"))
    lu.assertIsTrue(algorithm.starts_with("абс", "аб"))
    lu.assertIsFalse(algorithm.starts_with("абс", "ас"))
end

function TestEndsWith()
    lu.assertIsTrue(algorithm.ends_with("", ""))
    lu.assertIsTrue(algorithm.ends_with("12", "12"))
    lu.assertIsTrue(algorithm.ends_with("123", "23"))
    lu.assertIsTrue(algorithm.ends_with("1", ""))
    lu.assertIsFalse(algorithm.ends_with("", "1"))
    lu.assertIsFalse(algorithm.ends_with("23", "123"))
    lu.assertIsTrue(algorithm.ends_with("абс", "бс"))
    lu.assertIsFalse(algorithm.ends_with("абс", "ас"))
end


-- =====================================================  --

os.exit(lu.LuaUnit.run())
