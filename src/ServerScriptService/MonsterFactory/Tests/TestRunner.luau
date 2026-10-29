-- Minimal test runner. A spec module returns function(t) and calls t.it(name, fn).
-- Assertions: t.ok(cond, msg), t.eq(actual, expected, msg), t.near(a, b, tol, msg).
-- t.log(line) adds a line to the report (used by probability simulations).

local TestRunner = {}

function TestRunner.Run(specs: { ModuleScript })
	local lines, passed, failed = {}, 0, 0
	for _, specModule in specs do
		table.insert(lines, "## " .. specModule.Name)
		local tests = {}
		local t = {}
		function t.it(name, fn)
			table.insert(tests, { name = name, fn = fn })
		end
		function t.ok(cond, msg)
			if not cond then
				error(msg or "expected truthy", 2)
			end
		end
		function t.eq(a, b, msg)
			if a ~= b then
				error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
			end
		end
		function t.near(a, b, tol, msg)
			if math.abs(a - b) > tol then
				error(string.format("%s: expected %.6f +/- %.6f, got %.6f", msg or "near", b, tol, a), 2)
			end
		end
		function t.log(line)
			table.insert(lines, "    " .. line)
		end
		local okLoad, err = pcall(function()
			require(specModule)(t)
		end)
		if not okLoad then
			failed += 1
			table.insert(lines, "  FAIL (load) " .. tostring(err))
		end
		for _, test in tests do
			local ok, e = pcall(test.fn)
			if ok then
				passed += 1
				table.insert(lines, "  PASS " .. test.name)
			else
				failed += 1
				table.insert(lines, "  FAIL " .. test.name .. " -> " .. tostring(e))
			end
			task.wait() -- keep Studio responsive between tests
		end
	end
	table.insert(lines, string.format("TOTAL: %d passed, %d failed", passed, failed))
	return table.concat(lines, "\n"), passed, failed
end

return TestRunner
