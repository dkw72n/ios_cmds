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
    function string:printable(s)
        if not s then s = '' end
        return self:gsub('[^%w%p]', "")
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

--[[
#define PROC_ALL_PIDS           1
#define PROC_PGRP_ONLY          2
#define PROC_TTY_ONLY           3
#define PROC_UID_ONLY           4
#define PROC_RUID_ONLY          5
#define PROC_PPID_ONLY          6
#define PROC_KDBG_ONLY          7

#define PROX_FDTYPE_ATALK       0
#define PROX_FDTYPE_VNODE       1
#define PROX_FDTYPE_SOCKET      2
#define PROX_FDTYPE_PSHM        3
#define PROX_FDTYPE_PSEM        4
#define PROX_FDTYPE_KQUEUE      5
#define PROX_FDTYPE_PIPE        6
#define PROX_FDTYPE_FSEVENTS    7
#define PROX_FDTYPE_NETPOLICY   9
#define PROX_FDTYPE_CHANNEL     10
#define PROX_FDTYPE_NEXUS       11

/* Flavors for proc_pidinfo() */
#define PROC_PIDLISTFDS                 1


]]

local PROC_PIDLISTFDS = 1
local PROC_PIDTBSDINFO = 3 
-- print("Hi")
-- print(unsafe)

-- print("libc = ", libc)
local task_self = U.readu32(U.dlsym(libc, "mach_task_self_"))
local mach_task_self = U.dlsym(libc, "mach_task_self");
local errno = (function() 
    local _error = U.dlsym(libc, "__error");
    local _errno = U.call(_error)    
    return function()
        return U.readu32(_errno)
    end
end)()

local proc_pidinfo = (function()
    local _func = U.dlsym(libc, "proc_pidinfo");
    return function(pid, flavor, arg, prealloc)
        local l = prealloc
        if l == nil then 
            l = U.call(_func, pid, flavor, arg, 0, 0)
            if l == 0 then
                print("[!] failed to get length")
                return nil
            end
        end
        local buf = string.rep('f', l)
        l = U.call(_func, pid, flavor, arg, buf, buf:len())
        if l == 0 then 
            return nil
        end
        return buf:sub(1, l) 
    end
end)()
local proc_listpids = (function()
    local _func = U.dlsym(libc, "proc_listpids");
    return function(flavor, typeinfo)
        local ret = {}
        local n = U.call(_func, flavor, typeinfo, 0, 0)
        if n == 0 then return nil end
        local buf = string.rep('a', n + 100)
        n = U.call(_func, flavor, typeinfo, buf, buf:len())
        if n == 0 then return nil end
        if n >= buf:len() then return nil end
        for i = 0, n-1, 4 do 
            -- print(buf:u32(i))
            table.insert(ret, buf:u32(i))
        end
        return ret
    end
end)()
local proc_pidfdinfo = (function()
    local _func = U.dlsym(libc, "proc_pidfdinfo");
    return function(pid, fd, flavor)
        local ret = {}
        local n = 2048
        local buf = string.rep('a', n)
        n = U.call(_func, pid, fd, flavor, buf, buf:len())
        if n == 0 then 
            print("err:", errno())
            return nil 
        end
        if n >= buf:len() then return nil end
        return buf:sub(1, n)
    end
end)()
local function parse_fdinfo(s)
    local ret = {}
    for i = 0, s:len()-1, 8 do
        table.insert(ret, 
            {
                fd=s:u32(i),
                ty=s:u32(i+4)
            })
    end
    return ret
end

local parse_tbsdinfo = function(info)
    --[[
struct proc_bsdinfo {
	uint32_t                pbi_flags;              /* 64bit; emulated etc */
	uint32_t                pbi_status;
	uint32_t                pbi_xstatus;
	uint32_t                pbi_pid;
	uint32_t                pbi_ppid;
	uid_t                   pbi_uid;
	gid_t                   pbi_gid;
	uid_t                   pbi_ruid;
	gid_t                   pbi_rgid;
	uid_t                   pbi_svuid;
	gid_t                   pbi_svgid;
	uint32_t                rfu_1;                  /* reserved */
	char                    pbi_comm[MAXCOMLEN];
	char                    pbi_name[2 * MAXCOMLEN];  /* empty if no name is registered */
	uint32_t                pbi_nfiles;
	uint32_t                pbi_pgid;
	uint32_t                pbi_pjobc;
	uint32_t                e_tdev;                 /* controlling tty dev */
	uint32_t                e_tpgid;                /* tty process group id */
	int32_t                 pbi_nice;
	uint64_t                pbi_start_tvsec;
	uint64_t                pbi_start_tvusec;
};
    ]]
    local flags = info:u32(0)
    local status = info:u32(4)
    local xstatus = info:u32(8)
    local pid = info:u32(12)
    local ppid = info:u32(16);
    local uid = info:u32(20);
    local gid = info:u32(24);
    local comm = info:cstr(24 + 6 * 4)
    local name = info:cstr(24 + 6 * 4 + 16)
    local nfiles = info:u32(24 + 6 * 4 + 16 + 32)
    return string.format("%-11d%-11d%-11d%-11d%-17s%-33s", uid, pid, ppid, nfiles, comm, name)
end
local pid_list = proc_listpids(1, 0)
print(string.format("%-11s%-11s%-11s%-11s%-17s%-33s", "UID", "PID", "PPID", "NFILES", "COMM", "NAME"))
for _, pid in ipairs(pid_list) do
    local info = proc_pidinfo(pid, PROC_PIDTBSDINFO, 1, 256)
    print(parse_tbsdinfo(info))
end
--[=[
local PID = 1
local fdlist = parse_fdinfo(proc_pidinfo(PID, PROC_PIDLISTFDS, 0))
for _, p in ipairs(fdlist) do
    local t2p = {
        [1] = 1, -- PROX_FDTYPE_VNODE -> PROC_PIDFDVNODEINFO
        [2] = 3,
        [4] = 4, -- PROX_FDTYPE_PSEM
        [5] = 7, -- PROX_FDTYPE_KQUEUE -> PROC_PIDFDKQUEUEINFO
    }
    local info = nil
    if t2p[p.ty] then info = proc_pidfdinfo(PID, p.fd, t2p[p.ty]) end
    if info then
        print(p.fd, p.ty, info:printable()) -- , proc_pidfdinfo(PID, p.fd, t2p[p.ty]):hex())
    else
        print(p.fd, p.ty)
    end
end
]=]