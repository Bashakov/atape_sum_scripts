--[[ like Python contextlib.ExitStack or Go defer

register callbacks function which will called on exit from scope
sample:
```lua
	local function test()
		EnterScope(function(defer)
			print('1')
			defer(print, 'exit 1')
			print('2')
			defer(print, 'exit 2')
			defer(error, 'error 2')
			error('error main')
			print('3')
			defer(print, 'exit 3')
		end)
	end

	test()
`````

expect output:
````` `
1
2
error: error 2
exit 2
exit 1
error: error main
`````
]]

function EnterScope(work_fn)
	local stack = {}
	local defer = function(defer_fn, ...)
		table.insert(stack, {fn=defer_fn, args = {...}})
	end

	local ok, msg = pcall(function() return work_fn(defer) end)

	for i = #stack, 1, -1 do
		local s = stack[i]
		local o, m = pcall(function()
			s.fn(table.unpack(s.args))
		end)
		if not o then
			print(m)
		end
	end

	if not ok then
		error(msg)
	else
		return msg
	end
end
