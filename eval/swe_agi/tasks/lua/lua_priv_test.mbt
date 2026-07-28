///|
test "easy/happy/tables" {
  let src =
    #|local t = { a = 1, [2] = "b" }
    #|assert(t.a == 1)
    #|assert(t[2] == "b")
    #|t.a = t.a + 2
    #|assert(t.a == 3)
    #|
  exec_ok(src)
}

///|
test "easy/happy/control-flow" {
  let src =
    #|local sum = 0
    #|for i = 1, 5 do
    #|  sum = sum + i
    #|end
    #|assert(sum == 15)
    #|
  exec_ok(src)
}

///|
test "easy/happy/booleans-and-nil" {
  let src =
    #|local a = nil
    #|local b = false
    #|assert(a == nil)
    #|assert(b == false)
    #|assert((true and 1) == 1)
    #|assert((false or 2) == 2)
    #|assert(type(a) == "nil")
    #|assert(type(b) == "boolean")
    #|
  exec_ok(src)
}

///|
test "easy/happy/if-elseif-else" {
  let src =
    #|local function sign(x)
    #|  if x < 0 then
    #|    return -1
    #|  elseif x == 0 then
    #|    return 0
    #|  else
    #|    return 1
    #|  end
    #|end
    #|assert(sign(-3) == -1)
    #|assert(sign(0) == 0)
    #|assert(sign(5) == 1)
    #|
  exec_ok(src)
}

///|
test "easy/happy/while-repeat" {
  let src =
    #|local i = 0
    #|local sum = 0
    #|while i < 3 do
    #|  i = i + 1
    #|  sum = sum + i
    #|end
    #|assert(sum == 6)
    #|local j = 0
    #|repeat
    #|  j = j + 1
    #|until j == 3
    #|assert(j == 3)
    #|
  exec_ok(src)
}

///|
test "easy/happy/for-step" {
  let src =
    #|local s = 0
    #|for i = 5, 1, -2 do
    #|  s = s + i
    #|end
    #|assert(s == 9)
    #|
  exec_ok(src)
}

///|
test "easy/happy/bitwise-ops" {
  // From testes/constructs.lua (bitwise precedence basics)
  let src =
    #|assert(0xF0 & 0xCC == 0xC0)
    #|assert(0xF0 | 0x0F == 0xFF)
    #|assert(0xF0 ~ 0x0F == 0xFF)
    #|assert((1 << 3) == 8)
    #|assert((16 >> 2) == 4)
    #|
  exec_ok(src)
}

///|
test "easy/happy/string-sub-find" {
  let src =
    #|local s = "abcdef"
    #|assert(string.sub(s, 2, 4) == "bcd")
    #|local i, j = string.find(s, "cd")
    #|assert(i == 3 and j == 4)
    #|
  exec_ok(src)
}

///|
test "easy/happy/table-length" {
  let src =
    #|local t = { "a", "b", "c" }
    #|assert(#t == 3)
    #|t[4] = "d"
    #|assert(#t == 4)
    #|
  exec_ok(src)
}

///|
test "easy/happy/tonumber-tostring" {
  let src =
    #|assert(tonumber("12") == 12)
    #|assert(tonumber("0x10") == 16)
    #|assert(tostring(12) == "12")
    #|
  exec_ok(src)
}

///|
test "easy/happy/check-syntax" {
  let src =
    #|local ok = 1
    #|assert(ok == 1)
    #|
  exec_ok(src)
}

///|
test "easy/error/syntax-missing-end" {
  let src =
    #|assert(true)
    #|if true then
    #|  assert(1 == 1)
    #|-- missing end
    #|
  exec_syntax_error(src)
}

///|
test "easy/error/runtime-assert" {
  let src =
    #|assert(true)
    #|assert(false, "boom")
    #|
  exec_runtime_error(src)
}

///|
test "easy/error/runtime-index-nil" {
  let src =
    #|local t = nil
    #|t[1] = 1
    #|
  exec_runtime_error(src)
}

///|
test "easy/error/runtime-concat-table" {
  let src =
    #|local t = {}
    #|local s = "a" .. t
    #|
  exec_runtime_error(src)
}

///|
test "hard/happy/coroutine-status" {
  let src =
    #|local co = coroutine.create(function()
    #|  coroutine.yield(1)
    #|  return 2
    #|end)
    #|assert(coroutine.status(co) == "suspended")
    #|local ok, v = coroutine.resume(co)
    #|assert(ok and v == 1 and coroutine.status(co) == "suspended")
    #|ok, v = coroutine.resume(co)
    #|assert(ok and v == 2 and coroutine.status(co) == "dead")
    #|
  exec_ok(src)
}

///|
test "hard/happy/coroutine-tailcall-yield" {
  // From testes/coroutine.lua (yields in tail calls)
  let src =
    #|local function foo(i) return coroutine.yield(i) end
    #|local f = coroutine.wrap(function()
    #|  for i = 1, 10 do
    #|    assert(foo(i) == _G.x)
    #|  end
    #|  return "a"
    #|end)
    #|for i = 1, 10 do _G.x = i; assert(f(i) == i) end
    #|_G.x = "xuxu"; assert(f("xuxu") == "a")
    #|
  exec_ok(src)
}

///|
test "hard/happy/vararg-select-negative" {
  // From testes/vararg.lua (negative indices to select)
  let src =
    #|local a = {select(-2, 3, 5, 7)}
    #|assert(a[1] == 5 and a[2] == 7 and a[3] == nil)
    #|
  exec_ok(src)
}

///|
test "hard/happy/vararg-tailcall-missing" {
  // From testes/vararg.lua (missing arguments in tail call)
  let src =
    #|local function f(a, b, c) return c, b end
    #|local function g() return f(1, 2) end
    #|local x, y = g()
    #|assert(x == nil and y == 2)
    #|
  exec_ok(src)
}

///|
test "hard/happy/metatable-add" {
  let src =
    #|local mt = {}
    #|mt.__add = function(a, b)
    #|  return { value = a.value + b.value }
    #|end
    #|local a = setmetatable({ value = 2 }, mt)
    #|local b = setmetatable({ value = 3 }, mt)
    #|local c = a + b
    #|assert(c.value == 5)
    #|
  exec_ok(src)
}

///|
test "hard/happy/metatable-index-method" {
  let src =
    #|local proto = {}
    #|function proto:greet()
    #|  return "hi " .. self.name
    #|end
    #|local obj = setmetatable({ name = "lua" }, { __index = proto })
    #|assert(obj:greet() == "hi lua")
    #|
  exec_ok(src)
}

///|
test "hard/happy/metatable-index-function" {
  let src =
    #|local base = { x = 7 }
    #|local t = setmetatable({}, {
    #|  __index = function(_, k) return base[k] end,
    #|})
    #|assert(t.x == 7)
    #|
  exec_ok(src)
}

///|
test "hard/happy/metatable-newindex" {
  // From testes/events.lua (newindex behavior)
  let src =
    #|local t = {}
    #|local mt = {}
    #|mt.__newindex = function(tbl, k, v)
    #|  rawset(tbl, k, v * 2)
    #|end
    #|setmetatable(t, mt)
    #|t.a = 5
    #|assert(t.a == 10)
    #|
  exec_ok(src)
}

///|
test "hard/happy/metatable-call" {
  let src =
    #|local t = {}
    #|setmetatable(t, { __call = function(_, a, b) return a + b end })
    #|assert(t(2, 3) == 5)
    #|
  exec_ok(src)
}

///|
test "hard/happy/rawget-rawset" {
  let src =
    #|local t = setmetatable({}, { __index = function() return 99 end })
    #|assert(t.missing == 99)
    #|rawset(t, "missing", 10)
    #|assert(rawget(t, "missing") == 10)
    #|assert(rawequal(rawget(t, "missing"), 10))
    #|
  exec_ok(src)
}

///|
test "hard/happy/rawlen-metatable" {
  // From testes/events.lua (rawlen and __len)
  let src =
    #|local t = setmetatable({ 1, 2, 3 }, { __len = function() return 10 end })
    #|assert(#t == 10 and rawlen(t) == 3)
    #|assert(rawlen("abc") == 3)
    #|local ok = pcall(rawlen, 34)
    #|assert(not ok)
    #|
  exec_ok(src)
}

///|
test "hard/happy/table-sort-comparator" {
  // From testes/sort.lua (table.sort basic ordering)
  let src =
    #|local t = { 3, 1, 4, 2 }
    #|table.sort(t)
    #|assert(t[1] == 1 and t[4] == 4)
    #|table.sort(t, function(a, b) return a > b end)
    #|assert(t[1] == 4 and t[4] == 1)
    #|
  exec_ok(src)
}

///|
test "hard/happy/multi-return" {
  let src =
    #|local function swap(a, b)
    #|  return b, a
    #|end
    #|local x, y = swap(1, 2)
    #|assert(x == 2 and y == 1)
    #|
  exec_ok(src)
}

///|
test "hard/error/runtime-yield-outside" {
  let src =
    #|coroutine.yield()
    #|
  exec_runtime_error(src)
}

///|
test "hard/error/runtime-bad-coroutine" {
  let src =
    #|assert(true)
    #|coroutine.resume({})
    #|
  exec_runtime_error(src)
}

///|
test "hard/happy/metatable-tostring" {
  let src =
    #|local t = setmetatable({}, {
    #|  __tostring = function(self) return "custom string" end
    #|})
    #|assert(tostring(t) == "custom string")
    #|
  exec_ok(src)
}

///|
test "hard/happy/metatable-eq" {
  let src =
    #|local mt = {
    #|  __eq = function(a, b) return a.value == b.value end
    #|}
    #|local a = setmetatable({ value = 42 }, mt)
    #|local b = setmetatable({ value = 42 }, mt)
    #|local c = setmetatable({ value = 99 }, mt)
    #|assert(a == b)
    #|assert(not (a == c))
    #|
  exec_ok(src)
}

///|
test "hard/happy/metatable-concat" {
  let src =
    #|local mt = {
    #|  __concat = function(a, b) return a.text .. "-" .. b.text end
    #|}
    #|local x = setmetatable({ text = "hello" }, mt)
    #|local y = setmetatable({ text = "world" }, mt)
    #|local result = x .. y
    #|assert(result == "hello-world")
    #|
  exec_ok(src)
}

///|
test "hard/happy/metatable-len" {
  let src =
    #|local t = setmetatable({ 1, 2, 3, 4, 5 }, {
    #|  __len = function(self) return 100 end
    #|})
    #|assert(#t == 100)
    #|
  exec_ok(src)
}

///|
test "hard/happy/metatable-lt-le" {
  let src =
    #|local mt = {
    #|  __lt = function(a, b) return a.value < b.value end,
    #|  __le = function(a, b) return a.value <= b.value end,
    #|}
    #|local a = setmetatable({ value = 1 }, mt)
    #|local b = setmetatable({ value = 2 }, mt)
    #|assert(a < b)
    #|assert(a <= b)
    #|assert(not (b < a))
    #|
  exec_ok(src)
}

// _ENV environment manipulation tests

///|
test "hard/happy/env-manipulation" {
  let src =
    #|local env = { x = 10, print = print, assert = assert }
    #|local f = load("return x", "test", "t", env)
    #|assert(f() == 10)
    #|
  exec_ok(src)
}

///|
test "hard/happy/env-sandbox" {
  let src =
    #|local sandbox = setmetatable({}, {
    #|  __index = function(_, k)
    #|    if k == "print" then return print end
    #|    if k == "assert" then return assert end
    #|    return nil
    #|  end
    #|})
    #|local code = [[
    #|  local x = 5
    #|  assert(x == 5)
    #|]]
    #|local f = load(code, "sandbox", "t", sandbox)
    #|f()
    #|
  exec_ok(src)
}

// Number parsing edge cases

///|
test "hard/happy/number-hex-float" {
  let src =
    #|assert(0x1p0 == 1.0)
    #|assert(0x1p1 == 2.0)
    #|assert(0x1p-1 == 0.5)
    #|assert(0x1.8p0 == 1.5)
    #|assert(0xABCp4 == 0xABC0)
    #|
  exec_ok(src)
}

///|
test "hard/happy/number-integer-limits" {
  let src =
    #|local maxint = math.maxinteger
    #|local minint = math.mininteger
    #|assert(maxint > 0)
    #|assert(minint < 0)
    #|assert(maxint + 1 < maxint)  -- wrap around
    #|
  exec_ok(src)
}

///|
test "hard/happy/number-division-modes" {
  let src =
    #|assert(7 // 3 == 2)       -- floor division
    #|assert(-7 // 3 == -3)     -- floor towards negative infinity
    #|assert(7 / 3 > 2.3)       -- float division
    #|assert(7 % 3 == 1)        -- modulo
    #|assert(-7 % 3 == 2)       -- modulo with negative
    #|
  exec_ok(src)
}

// String pattern frontier matching

///|
test "hard/happy/string-pattern-frontier" {
  let src =
    #|local s = "the quick brown fox"
    #|local word = string.match(s, "%f[%a]%a+")
    #|assert(word == "the")
    #|
    #|local count = 0
    #|for w in string.gmatch(s, "%f[%a]%a+") do
    #|  count = count + 1
    #|end
    #|assert(count == 4)
    #|
  exec_ok(src)
}

///|
test "hard/happy/string-pattern-balanced" {
  let src =
    #|local s = "(a(b)c)"
    #|local inner = string.match(s, "%b()")
    #|assert(inner == "(a(b)c)")
    #|
  exec_ok(src)
}

// Coroutine error handling

///|
test "hard/happy/coroutine-error-handling" {
  let src =
    #|local co = coroutine.create(function()
    #|  error("test error")
    #|end)
    #|local ok, err = coroutine.resume(co)
    #|assert(not ok)
    #|assert(string.find(err, "test error"))
    #|assert(coroutine.status(co) == "dead")
    #|
  exec_ok(src)
}

///|
test "hard/happy/coroutine-multiple-values" {
  let src =
    #|local co = coroutine.create(function(a, b, c)
    #|  return a + b + c, a * b * c
    #|end)
    #|local ok, sum, product = coroutine.resume(co, 2, 3, 4)
    #|assert(ok)
    #|assert(sum == 9)
    #|assert(product == 24)
    #|
  exec_ok(src)
}

///|
test "hard/happy/coroutine-nested" {
  let src =
    #|local inner = coroutine.create(function()
    #|  coroutine.yield(1)
    #|  return 2
    #|end)
    #|local outer = coroutine.create(function()
    #|  local ok, v = coroutine.resume(inner)
    #|  coroutine.yield(v + 10)
    #|  ok, v = coroutine.resume(inner)
    #|  return v + 20
    #|end)
    #|local ok, r1 = coroutine.resume(outer)
    #|assert(ok and r1 == 11)
    #|ok, r1 = coroutine.resume(outer)
    #|assert(ok and r1 == 22)
    #|
  exec_ok(src)
}

///|
test "mid/error/runtime-call-nil" {
  let src =
    #|assert(true)
    #|local f = nil
    #|f()
    #|
  exec_runtime_error(src)
}

///|
test "mid/error/runtime-bad-table-insert" {
  // From testes/sort.lua (wrong number of arguments)
  let src =
    #|table.insert({}, 2, 3, 4)
    #|
  exec_runtime_error(src)
}

///|
test "mid/error/runtime-math-floor-type" {
  let src =
    #|math.floor("a")
    #|
  exec_runtime_error(src)
}

///|
test "mid/error/syntax-vararg-position" {
  // From testes/vararg.lua (vararg must be last)
  let src =
    #|local function f(..., a)
    #|  return a
    #|end
    #|
  exec_syntax_error(src)
}

///|
test "mid/error/syntax-bad-for" {
  let src =
    #|assert(true)
    #|for i = 1, 3, do
    #|  assert(i > 0)
    #|end
    #|
  exec_syntax_error(src)
}

///|
test "mid/happy/varargs-select" {
  let src =
    #|local function f(...)
    #|  return select("#", ...), select(2, ...)
    #|end
    #|local n, b, c = f(10, 20, 30)
    #|assert(n == 3 and b == 20 and c == 30)
    #|
  exec_ok(src)
}

///|
test "mid/happy/base-pcall-xpcall" {
  let src =
    #|local ok, err = pcall(function() error("boom") end)
    #|assert(not ok and string.find(err, "boom"))
    #|local function handler(msg) return "handled:" .. msg end
    #|local ok2, res = xpcall(function() error("bad") end, handler)
    #|assert(not ok2 and string.find(res, "handled:"))
    #|
  exec_ok(src)
}

///|
test "mid/happy/load-return" {
  let src =
    #|local f = assert(load("return 2 + 3"))
    #|assert(f() == 5)
    #|
  exec_ok(src)
}

///|
test "mid/happy/table-library" {
  let src =
    #|local t = { "a", "b" }
    #|table.insert(t, 2, "x")
    #|assert(table.concat(t, ",") == "a,x,b")
    #|local removed = table.remove(t, 1)
    #|assert(removed == "a")
    #|assert(table.concat(t, ",") == "x,b")
    #|
  exec_ok(src)
}

///|
test "mid/happy/table-pack-unpack" {
  let src =
    #|local t = table.pack(1, nil, 3)
    #|assert(t.n == 3)
    #|local a, b, c = table.unpack(t, 1, t.n)
    #|assert(a == 1 and b == nil and c == 3)
    #|
  exec_ok(src)
}

///|
test "mid/happy/table-move" {
  let src =
    #|local src = { 1, 2, 3 }
    #|local dst = {}
    #|table.move(src, 1, 3, 1, dst)
    #|assert(dst[1] == 1 and dst[2] == 2 and dst[3] == 3)
    #|
  exec_ok(src)
}

///|
test "mid/happy/string-patterns" {
  let src =
    #|local s = "abc123xyz"
    #|local letters, digits = string.match(s, "(%a+)(%d+)")
    #|assert(letters == "abc")
    #|assert(digits == "123")
    #|local replaced, n = string.gsub("a1b2", "%d", "x")
    #|assert(replaced == "axbx")
    #|assert(n == 2)
    #|
  exec_ok(src)
}

///|
test "mid/happy/string-byte-char" {
  let src =
    #|local b = string.byte("abc", 2)
    #|assert(b == 98)
    #|local s = string.char(97, 98, 99)
    #|assert(s == "abc")
    #|
  exec_ok(src)
}

///|
test "mid/happy/string-gsub-captures" {
  let src =
    #|local out, n = string.gsub("a1b2", "(%d)", "%1%1")
    #|assert(out == "a11b22")
    #|assert(n == 2)
    #|
  exec_ok(src)
}

///|
test "mid/happy/generic-for" {
  let src =
    #|local t = { a = 1, b = 2 }
    #|local sum = 0
    #|for _, v in pairs(t) do
    #|  sum = sum + v
    #|end
    #|assert(sum == 3)
    #|
  exec_ok(src)
}

///|
test "mid/happy/math-basics" {
  // From testes/math.lua (integer/float checks)
  let src =
    #|assert(math.type(1) == "integer")
    #|assert(math.type(1.5) == "float")
    #|assert(math.tointeger(5.0) == 5)
    #|assert(math.tointeger(5.2) == nil)
    #|assert(math.floor(-1.2) == -2)
    #|local a, b = math.modf(3.5)
    #|assert(a == 3.0 and b == 0.5)
    #|
  exec_ok(src)
}

///|
test "mid/happy/string-find-patterns" {
  let src =
    #|local s = "Hello, World!"
    #|local i, j = string.find(s, "World")
    #|assert(i == 8 and j == 12)
    #|
    #|local i2, j2 = string.find(s, "o", 6)
    #|assert(i2 == 9)
    #|
    #|local plain_i = string.find(s, ".", 1, true)
    #|assert(plain_i == nil)  -- no literal dot
    #|
  exec_ok(src)
}

///|
test "mid/happy/string-format" {
  let src =
    #|assert(string.format("%d", 42) == "42")
    #|assert(string.format("%s", "hello") == "hello")
    #|assert(string.format("%x", 255) == "ff")
    #|assert(string.format("%X", 255) == "FF")
    #|assert(string.format("%.2f", 3.14159) == "3.14")
    #|assert(string.format("%05d", 7) == "00007")
    #|
  exec_ok(src)
}

///|
test "mid/happy/string-rep" {
  let src =
    #|assert(string.rep("ab", 3) == "ababab")
    #|assert(string.rep("x", 5) == "xxxxx")
    #|assert(string.rep("", 100) == "")
    #|assert(string.rep("a", 0) == "")
    #|assert(string.rep("ab", 3, "-") == "ab-ab-ab")
    #|
  exec_ok(src)
}

///|
test "mid/happy/string-reverse" {
  let src =
    #|assert(string.reverse("hello") == "olleh")
    #|assert(string.reverse("") == "")
    #|assert(string.reverse("a") == "a")
    #|
  exec_ok(src)
}

///|
test "mid/happy/math-minmax" {
  let src =
    #|assert(math.max(1, 2, 3) == 3)
    #|assert(math.min(1, 2, 3) == 1)
    #|assert(math.max(-5) == -5)
    #|assert(math.min(-5, 0, 5) == -5)
    #|
  exec_ok(src)
}

///|
test "mid/happy/math-abs-sign" {
  let src =
    #|assert(math.abs(-5) == 5)
    #|assert(math.abs(5) == 5)
    #|assert(math.abs(0) == 0)
    #|
  exec_ok(src)
}

///|
test "mid/happy/math-trigonometry" {
  let src =
    #|local pi = math.pi
    #|assert(math.sin(0) == 0)
    #|assert(math.cos(0) == 1)
    #|assert(math.abs(math.sin(pi / 2) - 1) < 0.0001)
    #|assert(math.abs(math.cos(pi) + 1) < 0.0001)
    #|
  exec_ok(src)
}

///|
test "mid/happy/math-sqrt-pow" {
  let src =
    #|assert(math.sqrt(4) == 2)
    #|assert(math.sqrt(9) == 3)
    #|assert(2 ^ 3 == 8)
    #|assert(2 ^ 0 == 1)
    #|assert(2 ^ -1 == 0.5)
    #|
  exec_ok(src)
}

///|
test "mid/happy/table-concat-sep" {
  let src =
    #|local t = { "a", "b", "c" }
    #|assert(table.concat(t) == "abc")
    #|assert(table.concat(t, ", ") == "a, b, c")
    #|assert(table.concat(t, "-", 2, 3) == "b-c")
    #|
  exec_ok(src)
}

///|
test "mid/happy/ipairs-pairs" {
  let src =
    #|local t = { 10, 20, 30 }
    #|local sum = 0
    #|for i, v in ipairs(t) do
    #|  sum = sum + v
    #|end
    #|assert(sum == 60)
    #|
  exec_ok(src)
}

///|
test "mid/happy/next-iteration" {
  let src =
    #|local t = { a = 1, b = 2, c = 3 }
    #|local count = 0
    #|local k = nil
    #|repeat
    #|  k = next(t, k)
    #|  if k then count = count + 1 end
    #|until k == nil
    #|assert(count == 3)
    #|
  exec_ok(src)
}

///|
test "mid/happy/getmetatable-setmetatable" {
  let src =
    #|local t = {}
    #|local mt = { __index = { x = 10 } }
    #|setmetatable(t, mt)
    #|assert(getmetatable(t) == mt)
    #|assert(t.x == 10)
    #|
  exec_ok(src)
}

///|
test "mid/happy/runtime-tonumber-invalid" {
  let src =
    #|local n = tonumber("not a number")
    #|assert(n == nil)
    #|n = tonumber("42")
    #|assert(n == 42)
    #|
  exec_ok(src) // tonumber returns nil, doesn't error
}

///|
test "mid/error/runtime-concat-invalid" {
  let src =
    #|local s = "hello" .. {}
    #|
  exec_runtime_error(src)
}
