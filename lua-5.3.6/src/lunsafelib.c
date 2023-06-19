/*
** $Id: lunsafelib.c,v 0.0.0.1 2023/06/19 17:58:42 $
*/

#define ltablib_c
#define LUA_LIB

#include "lprefix.h"


#include <limits.h>
#include <stddef.h>
#include <string.h>
#include <dlfcn.h>

#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"


static int us_dlopen(lua_State* L) {
  size_t l;
  const char *s = luaL_checklstring(L, 1, &l);
  lua_Integer flag = luaL_optinteger(L, 2, 0x10/*RTLD_NOLOAD*/);
  uintptr_t ret = (uintptr_t)dlopen(s, flag);
  if (!ret){
    const char * err = dlerror();
    lua_pushnil(L);
    lua_pushstring(L, err);
    return 2;
  }
  lua_pushinteger(L, ret);
  return 1;
}

static int us_dlsym(lua_State* L) {
  void* lib = (void*)luaL_checkinteger(L, 1);
  const char* name = luaL_checkstring(L, 2);
  uintptr_t ret = (uintptr_t)(dlsym(lib, name));
  if (!ret){
    const char * err = dlerror();
    lua_pushnil(L);
    lua_pushstring(L, err);
    return 2;
  }
  lua_pushinteger(L, ret);
  return 1;
}

typedef uint8_t u8;
typedef int8_t s8;
typedef uint16_t u16;
typedef int16_t s16;
typedef uint32_t u32;
typedef int32_t s32;
typedef uint64_t u64;
typedef int64_t s64;
typedef float f32;
typedef double f64;

#define DECL_MEM_ACCESS(t) static int us_read ## t (lua_State* L){ \
  void* mem = (void*)luaL_checkinteger(L, 1); \
  lua_pushinteger(L, *(t*)mem); \
  return 1; \
} \
static int us_write ## t (lua_State* L){ \
  void* mem = (void*)luaL_checkinteger(L, 1); \
  t val = (t)luaL_checkinteger(L, 2); \
  *(t*)mem = val; \
  return 0; \
}

DECL_MEM_ACCESS(u8);
DECL_MEM_ACCESS(s8);
DECL_MEM_ACCESS(u16);
DECL_MEM_ACCESS(s16);
DECL_MEM_ACCESS(u32);
DECL_MEM_ACCESS(s32);
DECL_MEM_ACCESS(u64);
DECL_MEM_ACCESS(s64);
DECL_MEM_ACCESS(f32);
DECL_MEM_ACCESS(f64);

static int us_readstr(lua_State * L)
{
  void* mem = (void*)luaL_checkinteger(L, 1);
  lua_Integer l = luaL_optinteger(L, 2, -1);
  if (l == -1){
    lua_pushstring(L, mem);
  } else {
    lua_pushlstring(L, mem, l);
  }
  return 1;
}

static int us_writestr(lua_State * L)
{
  size_t l;
  void* mem = (void*)luaL_checkinteger(L, 1);
  const char* str = luaL_checklstring(L, 2, &l);
  memcpy(mem, str, l);
  return 0;
}

typedef uintptr_t (*func16_t)(
  uintptr_t, uintptr_t, uintptr_t, uintptr_t,
  uintptr_t, uintptr_t, uintptr_t, uintptr_t,
  uintptr_t, uintptr_t, uintptr_t, uintptr_t,
  uintptr_t, uintptr_t, uintptr_t, uintptr_t
);

static int us_call(lua_State * L)
{
  func16_t func = (func16_t)luaL_checkinteger(L, 1);
  int n = lua_gettop(L);
  uintptr_t args[16] = {0};
  char errmsg[128];
  if (n - 2 >= 16){
    return luaL_error(L, "error: too many args ( > 16)");
  }
  for (int i = 2; i <= n; ++ i){
    switch (lua_type(L, i)){
      case LUA_TNUMBER:
        args[i - 2] = (uintptr_t)luaL_checkinteger(L, i);
        break;
      case LUA_TSTRING:
        args[i - 2] = (uintptr_t)luaL_checkstring(L, i);
        break;
      default:
        sprintf(errmsg, "bad arg(%d): wrong type", i);
        return luaL_error(L, errmsg);
    }
  }
  uintptr_t ret = func(
    args[0], args[1], args[2], args[3],
    args[4], args[5], args[6], args[7],
    args[8], args[9], args[10], args[11],
    args[12], args[13], args[14], args[15]
  );
  lua_pushinteger(L, ret);
  return 1;
}

static int us_getcstr(lua_State *L)
{
  const char* ret = luaL_checkstring(L, 1);
  lua_pushinteger(L, (uintptr_t)ret);
  return 1;
}

static int ret0(){ return 0; }
static int us_ret0(lua_State *L)
{
  lua_pushinteger(L, (uintptr_t)&ret0);
  return 1;
}
/* }====================================================== */


static const luaL_Reg unsafe_funcs[] = {
  {"dlopen", us_dlopen},
  {"dlsym", us_dlsym},
  {"reads8", us_reads8},
  {"readu8", us_readu8},
  {"reads16", us_reads16},
  {"readu16", us_readu16},
  {"reads32", us_reads32},
  {"readu32", us_readu32},
  {"reads64", us_reads64},
  {"readu64", us_readu64},
  {"readf64", us_readf64},
  {"readf32", us_readf32},
  {"writes8", us_writes8},
  {"writeu8", us_writeu8},
  {"writes16", us_writes16},
  {"writeu16", us_writeu16},
  {"writes32", us_writes32},
  {"writeu32", us_writeu32},
  {"writes64", us_writes64},
  {"writeu64", us_writeu64},
  {"writef64", us_writef64},
  {"writef32", us_writef32},
  {"readstr", us_readstr},
  {"writestr", us_writestr},
  {"getcstr", us_getcstr},
  {"call", us_call},
  {"ret0", us_ret0},
#if 0
  {"callv0", us_callv0},
  {"callv1", us_callv1},
  {"callv2", us_callv2},
  {"callv3", us_callv3},
#endif
  {NULL, NULL}
};


LUAMOD_API int luaopen_unsafe (lua_State *L) {
  luaL_newlib(L, unsafe_funcs);
  return 1;
}

