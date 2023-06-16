

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

-- print("Hi")
-- print(unsafe)

-- print("libc = ", libc)
local task_self = U.readu32(U.dlsym(libc, "mach_task_self_"))
local mach_task_self = U.dlsym(libc, "mach_task_self");
-- print(string.format("%x", task_self))
local mach_vm_region = U.dlsym(libc, "mach_vm_region")
local task_for_pid = U.dlsym(libc, "task_for_pid")
local _vm_read = U.dlsym(libc, "vm_read")
local _getpid = U.dlsym(libc, "getpid")
local _proc_regionfilename = U.dlsym(libc, "proc_regionfilename")
--[[
print(mach_vm_region)
print(U.call(mach_task_self))
print(task_for_pid)
]]
local remote_task = string.rep('5', 8)
local address = string.rep('0', 8)
local size = string.rep('1', 8)
local ptr = U.getcstr
local VM_REGION_BASIC_INFO_64 = 9
local info = string.rep('2', 40)
local count = string.rep('3', 8)
local port = string.rep('4', 8)

U.writes64(ptr(remote_task), 0)
local PID = nil
for _, argx in ipairs(arg) do
    if argx:find('--pid=') == 1 then
        local pidstr = argx:gsub('%-%-pid=', '')
        PID = tonumber(pidstr)
        break
    end
end

if not PID then
    PID = U.call(_getpid)
end

assert(U.call(task_for_pid, task_self, PID, remote_task) == 0)

--[[
#pragma pack(push, 4)
#define VM_REGION_BASIC_INFO_64         9
struct vm_region_basic_info_64 {
	vm_prot_t               protection;
	vm_prot_t               max_protection;
	vm_inherit_t            inheritance;
	boolean_t               shared;
	boolean_t               reserved;
	memory_object_offset_t  offset;
	vm_behavior_t           behavior;
	unsigned short          user_wired_count;
};

#define	VM_PROT_NONE	((vm_prot_t) 0x00)

#define VM_PROT_READ	((vm_prot_t) 0x01)	/* read permission */
#define VM_PROT_WRITE	((vm_prot_t) 0x02)	/* write permission */
#define VM_PROT_EXECUTE	((vm_prot_t) 0x04)	/* execute permission */

/*
 *	Enumeration of valid values for vm_inherit_t.
 */

#define	VM_INHERIT_SHARE	((vm_inherit_t) 0)	/* share with child */
#define	VM_INHERIT_COPY		((vm_inherit_t) 1)	/* copy into child */
#define VM_INHERIT_NONE		((vm_inherit_t) 2)	/* absent from child */
#define	VM_INHERIT_DONATE_COPY	((vm_inherit_t) 3)	/* copy and delete */

#define VM_INHERIT_DEFAULT	VM_INHERIT_COPY
#define VM_INHERIT_LAST_VALID VM_INHERIT_NONE

]]

local vm_read = function(t, addr, size)
    local buf = string.rep('x', size)
    local cnt = string.rep('\x00', 8)
    local kr = U.call(_vm_read, t, addr, size, buf, cnt)
    if kr == 0 then
        return buf, cnt:u64(0)
    end
    return nil, string.format("Unable to read target task's memory @%x - kr 0x%x", addr, kr)
end

local proc_regionfilename = function(pid, addr)
    local buf = string.rep('\0', 2048)
    local l = U.call(_proc_regionfilename, pid, addr, buf, buf:len())
    return buf:sub(1,l+1)
end

local prot = function(n)
    local ret = {
        n & 0x1 ~= 0 and 'r' or '-',
        n & 0x2 ~= 0 and 'w' or '-',
        n & 0x4 ~= 0 and 'x' or '-',
    }
    return table.concat(ret)
end
local inher = function(n)
    local m = {
        [0] = "share",
        [1] = "copy",
        [2] = "none",
        [3] = "donate_copy"
    }
    return m[n] or tostring(n)
end
local task = PID and remote_task:u64(0) or task_self
local cur = 0
local prev = 0
local n = 0
while n < 100000 do
    U.writes64(ptr(address), cur)
    U.writes64(ptr(size), 0)
    U.writes64(ptr(count), info:len()/4)
    U.writes64(ptr(port), 0)

    local kr = U.call(mach_vm_region, task, address, size, VM_REGION_BASIC_INFO_64, info, count, port)
    if kr ~= 0 then
        break
    end
    if U.reads64(ptr(size)) == 0 then 
        break
    end
    local protection = info:u32(0)
    local max_protection = info:u32(4)
    local inheritance = info:u32(8)
    local shared = info:u32(12)
    local reserved = info:u32(16)
    local offset = info:u64(20)
    local behavior = info:u32(28)
    local user_wired_count = info:u32(32)
    local region_name = proc_regionfilename(PID, address:u64(0))
   
    print(
        string.format("[-] %x-%x %x", address:u64(0), address:u64(0) + size:u64(0), size:u64(0)), 
        prot(protection), prot(max_protection), inher(inheritance),
        shared == 0 and "private" or "shared", reserved,
        region_name:cstr(0) --[[, behavior, user_wired_count]]
    )
    prev = cur
    cur = U.reads64(ptr(address)) + U.reads64(ptr(size))
    assert(cur > prev)
    n = n + 1
end