include(FindPackageHandleStandardArgs)

if(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "ppc64le")
  # Moonjit is archived, but we need it to build on PPC64le.
  set(DEFAULT_TERRA_LUA "moonjit")
else()
  set(DEFAULT_TERRA_LUA "luajit")
endif()

set(TERRA_LUA "${DEFAULT_TERRA_LUA}" CACHE STRING "Build Terra against the specified Lua implementation")

if(TERRA_LUA STREQUAL "luajit")
  set(LUAJIT_NAME "LuaJIT")
  set(LUAJIT_BASE "luajit")
  set(LUAJIT_VERSION_MAJOR 2)
  set(LUAJIT_VERSION_MINOR 1)
  set(LUAJIT_VERSION_PATCH 1693268511)
  set(LUAJIT_VERSION_EXTRA "")
  set(LUAJIT_COMMIT "83954100dba9fc0cf5eeaf122f007df35ec9a604") # 2023-08-28
  set(LUAJIT_HASH_SHA256 "99b47959c953200e865f1d55dcbb19f887b1d6fc92b9d73192114115c62a7ac6")
  if(NOT LUAJIT_VERSION_COMMIT STREQUAL "")
    set(LUAJIT_URL_PREFIX "https://github.com/LuaJIT/LuaJIT/archive/")
  else()
    set(LUAJIT_URL_PREFIX "https://luajit.org/download/")
  endif()
elseif(TERRA_LUA STREQUAL "moonjit")
  set(LUAJIT_NAME "moonjit")
  set(LUAJIT_BASE "moonjit")
  set(LUAJIT_VERSION_MAJOR 2)
  set(LUAJIT_VERSION_MINOR 3)
  set(LUAJIT_VERSION_PATCH 0)
  set(LUAJIT_VERSION_EXTRA -dev)
  set(LUAJIT_COMMIT "eb7168839138591e0d2a1751122966603a8b87c8")
  set(LUAJIT_HASH_SHA256 "6086a84b9666233808dd8b19b9085ce7f68419e26cc266c6511eb96f8d7a5ce2")
  set(LUAJIT_URL_PREFIX "https://github.com/moonjit/moonjit/archive/")
else()
  message(FATAL_ERROR "TERRA_LUA must be one of 'luajit', 'moonjit'")
endif()

if(NOT LUAJIT_VERSION_COMMIT STREQUAL "")
  message(STATUS "Using Lua: ${LUAJIT_NAME} commit ${LUAJIT_COMMIT}")
else()
  message(STATUS "Using Lua: ${LUAJIT_NAME} release ${LUAJIT_VERSION_MAJOR}.${LUAJIT_VERSION_MINOR}.${LUAJIT_VERSION_PATCH}${LUAJIT_VERSION_EXTRA}")
endif()

if(NOT LUAJIT_VERSION_COMMIT STREQUAL "")
  set(LUAJIT_BASENAME "${LUAJIT_NAME}-${LUAJIT_COMMIT}")
  set(LUAJIT_URL "${LUAJIT_URL_PREFIX}/${LUAJIT_COMMIT}.tar.gz")
else()
  set(LUAJIT_BASENAME "${LUAJIT_NAME}-${LUAJIT_VERSION_MAJOR}.${LUAJIT_VERSION_MINOR}.${LUAJIT_VERSION_PATCH}${LUAJIT_VERSION_EXTRA}")
  set(LUAJIT_URL "${LUAJIT_URL_PREFIX}/${LUAJIT_BASENAME}.tar.gz")
endif()
set(LUAJIT_TAR "${PROJECT_BINARY_DIR}/${LUAJIT_BASENAME}.tar.gz")
set(LUAJIT_SOURCE_DIR "${PROJECT_BINARY_DIR}/${LUAJIT_BASENAME}")
set(LUAJIT_HEADER_BASENAMES lua.h lualib.h lauxlib.h luaconf.h)
if(WIN32)
  set(LUAJIT_INSTALL_PREFIX "${LUAJIT_SOURCE_DIR}/src")
  set(LUAJIT_INCLUDE_DIR "${LUAJIT_INSTALL_PREFIX}")
  set(LUAJIT_LIBRARY_NAME_WE "${LUAJIT_INSTALL_PREFIX}/lua51")
  set(LUAJIT_EXECUTABLE "${LUAJIT_INSTALL_PREFIX}/luajit.exe")
else()
  set(LUAJIT_INSTALL_PREFIX "${PROJECT_BINARY_DIR}/${LUAJIT_BASE}")
  set(LUAJIT_INCLUDE_DIR "${LUAJIT_INSTALL_PREFIX}/include/${LUAJIT_BASE}-${LUAJIT_VERSION_MAJOR}.${LUAJIT_VERSION_MINOR}")
  set(LUAJIT_SHARE_DIR "${LUAJIT_INSTALL_PREFIX}/share/${LUAJIT_BASE}-${LUAJIT_VERSION_MAJOR}.${LUAJIT_VERSION_MINOR}.${LUAJIT_VERSION_PATCH}${LUAJIT_VERSION_EXTRA}")
  set(LUAJIT_LIBRARY_NAME_WE "${LUAJIT_INSTALL_PREFIX}/lib/libluajit-5.1")
  set(LUAJIT_EXECUTABLE "${LUAJIT_INSTALL_PREFIX}/bin/${LUAJIT_BASE}-${LUAJIT_VERSION_MAJOR}.${LUAJIT_VERSION_MINOR}.${LUAJIT_VERSION_PATCH}${LUAJIT_VERSION_EXTRA}")
endif()

string(CONCAT
  LUAJIT_STATIC_LIBRARY
  "${LUAJIT_LIBRARY_NAME_WE}"
  "${CMAKE_STATIC_LIBRARY_SUFFIX}"
)

string(CONCAT
  LUAJIT_SHARED_LIBRARY
  "${LUAJIT_LIBRARY_NAME_WE}"
  "${CMAKE_SHARED_LIBRARY_SUFFIX}"
)

option(TERRA_SKIP_LUA_DOWNLOAD "do not download LuaJIT (used in Nix build because Nix pre-downloads LuaJIT)" OFF)
if(NOT TERRA_SKIP_LUA_DOWNLOAD)
  file(DOWNLOAD "${LUAJIT_URL}" "${LUAJIT_TAR}"
    EXPECTED_HASH SHA256=${LUAJIT_HASH_SHA256}
    STATUS LUAJIT_TAR_STATUS)
  list(GET LUAJIT_TAR_STATUS 0 LUAJIT_TAR_STATUS_CODE)
  if(NOT LUAJIT_TAR_STATUS_CODE EQUAL 0)
    list(GET LUAJIT_TAR_STATUS 1 LUAJIT_TAR_STATUS_MESSAGE)
    message(FATAL_ERROR "Failed to download LuaJIT release ${LUAJIT_URL}: ${LUAJIT_TAR_STATUS_MESSAGE}")
  endif()
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E tar xzf "${LUAJIT_TAR}"
  WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
)

foreach(LUAJIT_HEADER ${LUAJIT_HEADER_BASENAMES})
  list(APPEND LUAJIT_INSTALL_HEADERS "${LUAJIT_INCLUDE_DIR}/${LUAJIT_HEADER}")
endforeach()

list(APPEND LUAJIT_SHARED_LIBRARY_PATHS
  "${LUAJIT_SHARED_LIBRARY}"
)
if(UNIX AND NOT APPLE)
  list(APPEND LUAJIT_SHARED_LIBRARY_PATHS
    "${LUAJIT_SHARED_LIBRARY}.${LUAJIT_VERSION_MAJOR}"
    "${LUAJIT_SHARED_LIBRARY}.${LUAJIT_VERSION_MAJOR}.${LUAJIT_VERSION_MINOR}.${LUAJIT_VERSION_PATCH}"
  )
endif()

if(WIN32)
  add_custom_command(
    OUTPUT ${LUAJIT_STATIC_LIBRARY} ${LUAJIT_SHARED_LIBRARY_PATHS} ${LUAJIT_EXECUTABLE}
    DEPENDS ${LUAJIT_INSTALL_HEADERS}
    COMMAND msvcbuild
    WORKING_DIRECTORY ${LUAJIT_SOURCE_DIR}/src
    VERBATIM
  )

  install(
    FILES ${LUAJIT_SHARED_LIBRARY_PATHS}
    DESTINATION ${CMAKE_INSTALL_BINDIR}
  )

  install(
    FILES ${LUAJIT_STATIC_LIBRARY}
    DESTINATION ${CMAKE_INSTALL_LIBDIR}
  )

  file(MAKE_DIRECTORY "${LUAJIT_INSTALL_PREFIX}/lua/jit")

  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar tzf "${LUAJIT_TAR}"
    OUTPUT_VARIABLE LUAJIT_TAR_CONTENTS
  )

  string(REGEX MATCHALL
    "[^\\\\/\r\n]+/src/jit/[^\\\\/\r\n]+[.]lua"
    LUAJIT_LUA_SOURCE_PATHS
    ${LUAJIT_TAR_CONTENTS}
  )

  foreach(LUAJIT_SOURCE_PATH ${LUAJIT_LUA_SOURCE_PATHS})
    string(REGEX MATCH
      "[^\\\\/\r\n]+[.]lua"
      LUAJIT_SOURCE_NAME
      ${LUAJIT_SOURCE_PATH}
    )
    file(COPY "${LUAJIT_INSTALL_PREFIX}/jit/${LUAJIT_SOURCE_NAME}"
      DESTINATION "${LUAJIT_INSTALL_PREFIX}/lua/jit/"
    )
    list(APPEND LUAJIT_LUA_SOURCES
      "${LUAJIT_INSTALL_PREFIX}/lua/jit/${LUAJIT_SOURCE_NAME}"
    )
  endforeach()
else()
  find_program(MAKE_EXE NAMES gmake make)

  add_custom_command(
    OUTPUT ${LUAJIT_STATIC_LIBRARY} ${LUAJIT_SHARED_LIBRARY_PATHS} ${LUAJIT_EXECUTABLE} ${LUAJIT_INSTALL_HEADERS}
    DEPENDS ${LUAJIT_SOURCE_DIR}
    # MACOSX_DEPLOYMENT_TARGET is a workaround for https://github.com/LuaJIT/LuaJIT/issues/484
    # see also https://github.com/LuaJIT/LuaJIT/issues/575
    COMMAND ${CMAKE_COMMAND} -E env --unset=MAKEFLAGS ${MAKE_EXE} install "PREFIX=${LUAJIT_INSTALL_PREFIX}" "CC=${CMAKE_C_COMPILER}" "STATIC_CC=${CMAKE_C_COMPILER} -fPIC" CCDEBUG=$<$<CONFIG:Debug>:-g> XCFLAGS=-DLUAJIT_ENABLE_GC64 MACOSX_DEPLOYMENT_TARGET=10.7
    WORKING_DIRECTORY ${LUAJIT_SOURCE_DIR}
    VERBATIM
  )
endif()

foreach(LUAJIT_HEADER ${LUAJIT_HEADER_BASENAMES})
  list(APPEND LUAJIT_HEADERS ${PROJECT_BINARY_DIR}/include/terra/${LUAJIT_HEADER})
endforeach()

foreach(LUAJIT_HEADER ${LUAJIT_HEADER_BASENAMES})
  if(WIN32)
    file(COPY "${LUAJIT_INCLUDE_DIR}/${LUAJIT_HEADER}"
      DESTINATION "${PROJECT_BINARY_DIR}/include/terra/"
    )
  else()
    add_custom_command(
      OUTPUT ${PROJECT_BINARY_DIR}/include/terra/${LUAJIT_HEADER}
      DEPENDS
        ${LUAJIT_INCLUDE_DIR}/${LUAJIT_HEADER}
      COMMAND "${CMAKE_COMMAND}" -E copy "${LUAJIT_INCLUDE_DIR}/${LUAJIT_HEADER}" "${PROJECT_BINARY_DIR}/include/terra/"
      VERBATIM
    )
  endif()
  install(
    FILES ${PROJECT_BINARY_DIR}/include/terra/${LUAJIT_HEADER}
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/terra
  )
endforeach()

if(TERRA_SLIB_INCLUDE_LUAJIT)
  set(LUAJIT_OBJECT_DIR "${PROJECT_BINARY_DIR}/lua_objects")
  file(MAKE_DIRECTORY "${LUAJIT_OBJECT_DIR}")

  # Since we need the list of objects at configure time, best we can do
  # (without building LuaJIT right this very second) is to guess based
  # on the source files contained in the release tarball.
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar tzf "${LUAJIT_TAR}"
    OUTPUT_VARIABLE LUAJIT_TAR_CONTENTS
  )

  string(REGEX MATCHALL
    "[^/\n]+/src/l[ij][b_][^\n]+[.]c"
    LUAJIT_SOURCES
    ${LUAJIT_TAR_CONTENTS}
  )

  foreach(LUAJIT_SOURCE ${LUAJIT_SOURCES})
    string(REGEX MATCH
      "[^/\n]+[.]c"
      LUAJIT_SOURCE_BASENAME
      ${LUAJIT_SOURCE}
    )
    string(REGEX REPLACE
      [.]c .o
      LUAJIT_OBJECT_BASENAME
      ${LUAJIT_SOURCE_BASENAME}
    )
    list(APPEND LUAJIT_OBJECT_BASENAMES ${LUAJIT_OBJECT_BASENAME})
  endforeach()
  list(APPEND LUAJIT_OBJECT_BASENAMES lj_vm.o)

  foreach(LUAJIT_OBJECT ${LUAJIT_OBJECT_BASENAMES})
    list(APPEND LUAJIT_OBJECTS "${LUAJIT_OBJECT_DIR}/${LUAJIT_OBJECT}")
  endforeach()

  add_custom_command(
    OUTPUT ${LUAJIT_OBJECTS}
    DEPENDS ${LUAJIT_STATIC_LIBRARY}
    COMMAND "${CMAKE_AR}" x "${LUAJIT_STATIC_LIBRARY}"
    WORKING_DIRECTORY ${LUAJIT_OBJECT_DIR}
    VERBATIM
  )

  # Don't link libraries, since we're using the extracted object files.
  list(APPEND LUAJIT_LIBRARIES)
elseif(TERRA_STATIC_LINK_LUAJIT)
  if(APPLE)
    list(APPEND LUAJIT_LIBRARIES "-Wl,-force_load,${LUAJIT_STATIC_LIBRARY}")
  elseif(UNIX)
    list(APPEND LUAJIT_LIBRARIES
      -Wl,-export-dynamic
      -Wl,--whole-archive
      "${LUAJIT_STATIC_LIBRARY}"
      -Wl,--no-whole-archive
    )
  else()
    list(APPEND LUAJIT_LIBRARIES ${LUAJIT_STATIC_LIBRARY})
  endif()

  # Don't extract individual object files.
  list(APPEND LUAJIT_OBJECTS)
else()
  list(APPEND LUAJIT_LIBRARIES ${LUAJIT_SHARED_LIBRARY})

  # Make a copy of the LuaJIT shared library into the local build and
  # install so that all the directory structures are consistent.
  # Note: Need to copy all symlinks (*.so.0 etc.).
  foreach(LUAJIT_SHARED_LIBRARY_PATH ${LUAJIT_SHARED_LIBRARY_PATHS})
    get_filename_component(LUAJIT_SHARED_LIBRARY_NAME "${LUAJIT_SHARED_LIBRARY_PATH}" NAME)
    add_custom_command(
      OUTPUT ${PROJECT_BINARY_DIR}/lib/${LUAJIT_SHARED_LIBRARY_NAME}
      DEPENDS ${LUAJIT_SHARED_LIBRARY_PATH}
      COMMAND "${CMAKE_COMMAND}" -E copy "${LUAJIT_SHARED_LIBRARY_PATH}" "${PROJECT_BINARY_DIR}/lib/${LUAJIT_SHARED_LIBRARY_NAME}"
      VERBATIM
    )
    list(APPEND LUAJIT_SHARED_LIBRARY_BUILD_PATHS
      ${PROJECT_BINARY_DIR}/lib/${LUAJIT_SHARED_LIBRARY_NAME}
    )

    install(
      FILES ${LUAJIT_SHARED_LIBRARY_PATH}
      DESTINATION ${CMAKE_INSTALL_LIBDIR}
    )
  endforeach()

  # Don't extract individual object files.
  list(APPEND LUAJIT_OBJECTS)
endif()

add_custom_target(
  LuaJIT
  DEPENDS
    ${LUAJIT_STATIC_LIBRARY}
    ${LUAJIT_SHARED_LIBRARY_PATHS}
    ${LUAJIT_SHARED_LIBRARY_BUILD_PATHS}
    ${LUAJIT_EXECUTABLE}
    ${LUAJIT_HEADERS}
    ${LUAJIT_OBJECTS}
)

mark_as_advanced(
  DEFAULT_TERRA_LUA
  LUAJIT_BASENAME
  LUAJIT_URL
  LUAJIT_TAR
  LUAJIT_SOURCE_DIR
  LUAJIT_INCLUDE_DIR
  LUAJIT_HEADER_BASENAMES
  LUAJIT_OBJECT_DIR
  LUAJIT_LIBRARY
  LUAJIT_EXECUTABLE
  TERRA_SKIP_LUA_DOWNLOAD
)
