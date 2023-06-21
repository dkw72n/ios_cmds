local U = unsafe
local libc = U.dlopen("libSystem.B.dylib")
local hex = function(n) return string.format("0x%x", n) end
local _setup1, _errmsg1 = pcall(function()
    local apply = U.call
    function table:imap(fn)
      local ret = {}
      for i, v in ipairs(self) do
        table.insert(ret, fn(v))
      end
      return ret
    end
    print = log_print or print
    function string:u8(offset)
        return self:byte(offset + 1)
    end
    function string:u16(offset, be)
        local s = be and 1 or 0
        return (self:u8(offset) << (s*8)) + (self:u8(offset + 1) << ((1-s)*8))
    end
    function string:u32(offset, be)
        local s = be and 1 or 0
        return (self:u16(offset, be) << (s*16)) + (self:u16(offset + 2, be) << ((1-s)*16))
    end
    function string:u64(offset, be)
        local s = be and 1 or 0
        return (self:u32(offset, be) << (s*32)) + (self:u32(offset + 4, be) << ((1-s)*32))
    end
    function string:hex(s)
        if not s then s = '' end
        return self:gsub('.', function(c) return string.format("%s%02x", s, string.byte(c)) end)
    end
    function string:cstr(offset)
        local x = self:find('\0', offset + 1)
        return self:sub(offset + 1, x - 1)
    end
    
    --[[
    local _memcpy = ReadMem(GetFunctionsPtr() + 8)
    function string:load(p)
        local x = U.getcstr(self)
        U.writestr(p)
    end
    function string:store(p)
        apply(_memcpy, p, self, self:len())
    end
    ]]
end)
assert(_setup1, _errmsg1)
local printf = function(...)
    print(string.format(...))
end
-- print("Hi")
-- print(unsafe)

-- print("libc = ", libc)
local task_self = U.readu32(U.dlsym(libc, "mach_task_self_"))
local mach_task_self = U.dlsym(libc, "mach_task_self");
-- print(string.format("%x", task_self))
local mach_vm_region = U.dlsym(libc, "mach_vm_region")

local _vm_read = U.dlsym(libc, "mach_vm_read_overwrite")
local _vm_write = U.dlsym(libc, "mach_vm_write")
local _vm_remap = U.dlsym(libc, "mach_vm_remap")
local _vm_allocate = U.dlsym(libc, "vm_allocate")
local _vm_deallocate = U.dlsym(libc, "vm_deallocate")
local _vm_protect = U.dlsym(libc, "vm_protect")
local _getpid = U.dlsym(libc, "getpid")
local _proc_regionfilename = U.dlsym(libc, "proc_regionfilename")
local ptr = U.getcstr

local PID = 4032

local task_for_pid = (function()
    local _task_for_pid = U.dlsym(libc, "task_for_pid")
    assert(_task_for_pid ~= 0, "dlsym(task_for_pid)")
    return function(pid)
        local ret = string.rep('0', 8)
        U.writes64(ptr(ret), 0)
        if U.call(_task_for_pid, task_self, pid, ret) == 0 then
            return ret:u64(0)
        end
        return nil, "ERROR: task_for_pid:"
    end
end)()
local new_ptr = function(x)
    local ret = string.rep('0', 8)
    U.writes64(ptr(ret), x)
    return ret
end
print(task_for_pid(PID), _vm_remap)
local target_task = task_for_pid(PID)
local target_address = new_ptr(0)
local VM_FLAGS_FIXED = 0
local VM_FLAGS_ANYWHERE = 1

local mask = 0
local flags = 0
local src_task = task_self
local src_address = 0x104818000
local size = 0x4000 -- 0x10484c000 - src_address
local copy = 1
local cur_protection = new_ptr(5)
local max_protection = new_ptr(7)
local inheritance = 0
-- print(U.call(_vm_remap, src_task, target_address, size, mask, VM_FLAGS_ANYWHERE, src_task, src_address, copy, cur_protection, max_protection, inheritance))
-- print(string.format("%x %x %x", target_address:u64(0), cur_protection:u64(0), max_protection:u64(0)))
-- local p = U.dlsym(libc, "putc") - 0x34 + 0xb8
local PAGESIZE = 0x4000
local p = U.ret0()
local o = p % PAGESIZE
src_address = p - p % PAGESIZE
print(string.format("%x", U.readu32(p)), U.call(p), p % PAGESIZE)
-- print(U.call(_vm_remap, src_task, target_address, size, mask, VM_FLAGS_ANYWHERE, src_task, src_address, copy, cur_protection, max_protection, inheritance))
-- print(string.format("%x %x %x", target_address:u64(0), cur_protection:u64(0), max_protection:u64(0)))
-- print(U.call(target_address:u64(0) + o))


--[==[ -- SIGKILL: CODESIGNING
print(U.call(_vm_allocate, src_task, target_address, PAGESIZE, VM_FLAGS_ANYWHERE))
print(U.call(_vm_protect, src_task, target_address:u64(0), PAGESIZE, 0, 3))
U.writes64(target_address:u64(0), 0xd65f03c0) -- RET
print(U.call(_vm_protect, src_task, target_address:u64(0), PAGESIZE, 0, 5))
-- src_address = target_address:u64(0)

-- ]==]
assert(U.call(_vm_remap, target_task, target_address, size, mask, VM_FLAGS_ANYWHERE, src_task, src_address, copy, cur_protection, max_protection, inheritance) == 0)
printf("remap: %x %x %x", target_address:u64(0), cur_protection:u64(0), max_protection:u64(0))


local malloc_logger = U.dlsym(libc, "malloc_logger")
-- local OFFSET = U.dlsym(libc, "malloc") - 0x190EE64F8
-- local malloc_logger = OFFSET + 0x1F2C14048
printf("malloc_logger@%x: %x ", malloc_logger, U.readu64(malloc_logger))
printf("malloc %x", U.dlsym(libc, "malloc"))

local data = string.rep('v', 8)
local dataCnt = new_ptr(0)
assert(U.call(_vm_read, target_task, malloc_logger, 8, data, dataCnt) == 0)
printf("_vm_read:%x %x", data:u64(0), dataCnt:u64(0))
-- data = new_ptr(OFFSET + 0x1B9E51C48)
data = new_ptr(target_address:u64(0) + o)
assert(U.call(_vm_write, target_task, malloc_logger, data, 8) == 0)
--[==[
local dlerror = U.dlsym(libc, "dlerror")
local aa,bb = U.dlopen("/var/root/frida/usr/lib/frida/frida-agent.dylib",2)
print(tostring(aa), tostring(bb))
]==]