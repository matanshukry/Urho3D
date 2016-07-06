#
# Copyright (c) 2008-2016 the Urho3D project.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

# Save the original values of CC and CXX environment variables as they are not saved yet when no CMake toolchain file is being used
if (NOT CMAKE_CROSSCOMPILING)
    set (SAVED_CC $ENV{CC})
    set (SAVED_CXX $ENV{CXX})
endif ()

# Limit the supported build configurations
set (URHO3D_BUILD_CONFIGURATIONS Release RelWithDebInfo Debug)
set (DOC_STRING "Specify CMake build configuration (single-configuration generator only), possible values are Release (default), RelWithDebInfo, and Debug")
if (CMAKE_CONFIGURATION_TYPES)
    # For multi-configurations generator, such as VS and Xcode
    set (CMAKE_CONFIGURATION_TYPES ${URHO3D_BUILD_CONFIGURATIONS} CACHE STRING ${DOC_STRING} FORCE)
    unset (CMAKE_BUILD_TYPE)
else ()
    # For single-configuration generator, such as Unix Makefile generator
    if (CMAKE_BUILD_TYPE STREQUAL "")
        # If not specified then default to Release
        set (CMAKE_BUILD_TYPE Release)
    endif ()
    set (CMAKE_BUILD_TYPE ${CMAKE_BUILD_TYPE} CACHE STRING ${DOC_STRING} FORCE)
endif ()

# Define other useful variables not defined by CMake
if (CMAKE_GENERATOR STREQUAL Xcode)
    set (XCODE TRUE)
elseif (CMAKE_GENERATOR STREQUAL Ninja)
    set (NINJA TRUE)
elseif (CMAKE_GENERATOR MATCHES Visual)
    set (VS TRUE)
endif ()

# Rightfully we could have performed this inside a CMake/iOS toolchain file but we don't have one nor need for one for now
if (IOS)
    set (CMAKE_CROSSCOMPILING TRUE)
    set (CMAKE_XCODE_EFFECTIVE_PLATFORMS -iphoneos -iphonesimulator)
    set (CMAKE_OSX_SYSROOT iphoneos)    # Set Base SDK to "Latest iOS"
    # This is a CMake hack in order to make standard CMake check modules that use try_compile() internally work on iOS platform
    # The injected "flags" are not compiler flags, they are actually CMake variables meant for another CMake subprocess that builds the source file being passed in the try_compile() command
    # CAVEAT: these injected "flags" must always be kept at the end of the string variable, i.e. when adding more compiler flags later on then those new flags must be prepended in front of these flags instead
    set (CMAKE_REQUIRED_FLAGS ";-DSmileyHack=byYaoWT;-DCMAKE_MACOSX_BUNDLE=1;-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=0")
    if (NOT IOS_SYSROOT)
        execute_process (COMMAND xcodebuild -version -sdk ${CMAKE_OSX_SYSROOT} Path OUTPUT_VARIABLE IOS_SYSROOT OUTPUT_STRIP_TRAILING_WHITESPACE)   # Obtain iOS sysroot path
        set (IOS_SYSROOT ${IOS_SYSROOT} CACHE INTERNAL "Path to iOS system root")
    endif ()
    set (CMAKE_FIND_ROOT_PATH ${IOS_SYSROOT})
    set (IPHONEOS_DEPLOYMENT_TARGET "" CACHE STRING "Specify iOS deployment target (iOS platform only); default to latest installed iOS SDK if not specified, the minimum supported target is 3.0 due to constraint from SDL library")
    if (IPHONEOS_DEPLOYMENT_TARGET)
        set (CMAKE_XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET ${IPHONEOS_DEPLOYMENT_TARGET})
    endif ()
    set (CMAKE_XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES)
    # Workaround what appears to be a bug in CMake/Xcode generator, ensure the CMAKE_OSX_DEPLOYMENT_TARGET is set to empty for iOS build
    set (CMAKE_OSX_DEPLOYMENT_TARGET)
    unset (CMAKE_OSX_DEPLOYMENT_TARGET CACHE)
elseif (XCODE)
    set (CMAKE_OSX_SYSROOT macosx)    # Set Base SDK to "Latest OS X"
    if (NOT CMAKE_OSX_DEPLOYMENT_TARGET)
        # If not set, set to current running build system OS version by default
        execute_process (COMMAND sw_vers -productVersion OUTPUT_VARIABLE CURRENT_OSX_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE)
        string (REGEX REPLACE ^\([^.]+\\.[^.]+\).* \\1 CMAKE_OSX_DEPLOYMENT_TARGET ${CURRENT_OSX_VERSION})
        set (CMAKE_OSX_DEPLOYMENT_TARGET ${CMAKE_OSX_DEPLOYMENT_TARGET} CACHE STRING "Specify macOS deployment target (macOS platform only); default to current running macOS if not specified, the minimum supported target is 10.5 due to constraint from SDL library")
    endif ()
endif ()

include (CheckHost)
include (CheckCompilerToolchain)

# Extra linker flags for linking against indirect dependencies (linking shared lib with dependencies)
if (RPI)
    # Extra linker flags for Raspbian because it installs VideoCore libraries in the "/opt/vc/lib" directory (no harm in doing so for other distros)
    set (INDIRECT_DEPS_EXE_LINKER_FLAGS "${INDIRECT_DEPS_EXE_LINKER_FLAGS} -Wl,-rpath-link,\"${CMAKE_SYSROOT}/opt/vc/lib\"")      # CMAKE_SYSROOT is empty when not cross-compiling
endif ()
if (ARM AND CMAKE_SYSTEM_NAME STREQUAL Linux AND CMAKE_CROSSCOMPILING)
    # Cannot do this in the toolchain file because CMAKE_LIBRARY_ARCHITECTURE is not yet defined when CMake is processing toolchain file
    set (INDIRECT_DEPS_EXE_LINKER_FLAGS "${INDIRECT_DEPS_EXE_LINKER_FLAGS} -Wl,-rpath-link,\"${CMAKE_SYSROOT}/usr/lib/${CMAKE_LIBRARY_ARCHITECTURE}\":\"${CMAKE_SYSROOT}/lib/${CMAKE_LIBRARY_ARCHITECTURE}\"")
endif ()
set (CMAKE_REQUIRED_FLAGS "${INDIRECT_DEPS_EXE_LINKER_FLAGS} ${CMAKE_REQUIRED_FLAGS}")
set (CMAKE_EXE_LINKER_FLAGS "${INDIRECT_DEPS_EXE_LINKER_FLAGS} ${CMAKE_EXE_LINKER_FLAGS}")

# Define all supported build options
include (CMakeDependentOption)
option (URHO3D_C++11 "Enable C++11 standard")
cmake_dependent_option (IOS "Setup build for iOS platform" FALSE "XCODE" FALSE)
cmake_dependent_option (URHO3D_64BIT "Enable 64-bit build, the default is set based on the native ABI of the chosen compiler toolchain" ${NATIVE_64BIT} "NOT MSVC AND NOT ANDROID AND NOT (ARM AND NOT IOS) AND NOT WEB AND NOT POWERPC" ${NATIVE_64BIT})     # Intentionally only enable the option for iOS but not for tvOS as the latter is 64-bit only
option (URHO3D_ANGELSCRIPT "Enable AngelScript scripting support" TRUE)
option (URHO3D_LUA "Enable additional Lua scripting support" TRUE)
option (URHO3D_NAVIGATION "Enable navigation support" TRUE)
cmake_dependent_option (URHO3D_NETWORK "Enable networking support" TRUE "NOT WEB" FALSE)
option (URHO3D_PHYSICS "Enable physics support" TRUE)
option (URHO3D_URHO2D "Enable 2D graphics and physics support" TRUE)
if (ARM AND NOT ANDROID AND NOT RPI AND NOT IOS AND NOT TVOS)
    set (ARM_ABI_FLAGS "" CACHE STRING "Specify ABI compiler flags (ARM on Linux platform only); e.g. Orange-Pi Mini 2 could use '-mcpu=cortex-a7 -mfpu=neon-vfpv4'")
endif ()
if (IOS OR (RPI AND "${RPI_ABI}" MATCHES NEON) OR (ARM AND (URHO3D_64BIT OR "${ARM_ABI_FLAGS}" MATCHES neon)))    # Stringify in case RPI_ABI/ARM_ABI_FLAGS is not set explicitly
    # The 'NEON' CMake variable is already set by android.toolchain.cmake when the chosen ANDROID_ABI uses NEON
    set (NEON TRUE)
endif ()
# For Raspbery Pi, find Broadcom VideoCore IV firmware
if (RPI)
    # TODO: this logic is earmarked to be moved into SDL's CMakeLists.txt when refactoring the library dependency handling
    find_package (VideoCore REQUIRED)
    include_directories (SYSTEM ${VIDEOCORE_INCLUDE_DIRS})
    link_directories (${VIDEOCORE_LIBRARY_DIRS})
endif ()
if (CMAKE_PROJECT_NAME STREQUAL Urho3D)
    set (URHO3D_LIB_TYPE STATIC CACHE STRING "Specify Urho3D library type, possible values are STATIC (default) and SHARED")
    # The URHO3D_OPENGL option is not available on non-Windows platforms as they should always use OpenGL, i.e. URHO3D_OPENGL variable will always be forced to TRUE
    if (MSVC)
        # On MSVC compiler, default to false (i.e. prefers Direct3D)
        # OpenGL can be manually enabled with -DURHO3D_OPENGL=1, but Windows graphics card drivers are usually better optimized for Direct3D
        set (DEFAULT_OPENGL FALSE)
    else ()
        # On non-MSVC compiler on Windows platform, default to true to enable use of OpenGL instead of Direct3D
        # Direct3D can be manually enabled with -DURHO3D_OPENGL=0, but it is likely to fail unless the MinGW-w64 distribution is used due to dependency to Direct3D headers and libs
        set (DEFAULT_OPENGL TRUE)
    endif ()
    cmake_dependent_option (URHO3D_OPENGL "Use OpenGL instead of Direct3D (Windows platform only)" ${DEFAULT_OPENGL} "WIN32" TRUE)      # Force the variable to TRUE when not WIN32
    # On Windows platform Direct3D11 can be optionally chosen
    # Using Direct3D11 on non-MSVC compiler may require copying and renaming Microsoft official libraries (.lib to .a), else link failures or non-functioning graphics may result
    cmake_dependent_option (URHO3D_D3D11 "Use Direct3D11 instead of Direct3D9 (Windows platform only); overrides URHO3D_OPENGL option" FALSE "WIN32" FALSE)
    if (NOT ARM)
        # It is not possible to turn SSE off on 64-bit MSVC and it appears it is also not able to do so safely on 64-bit GCC
        cmake_dependent_option (URHO3D_SSE "Enable SSE/SSE2 instruction set (32-bit Web and Intel platforms only, including Android on Intel Atom); default to true on Intel and false on Web platform; the effective SSE level could be higher, see also URHO3D_DEPLOYMENT_TARGET and CMAKE_OSX_DEPLOYMENT_TARGET build options" ${HAVE_SSE2} "NOT URHO3D_64BIT" TRUE)
    endif ()
    cmake_dependent_option (URHO3D_3DNOW "Enable 3DNow! instruction set (Linux platform only); should only be used for older CPU with (legacy) 3DNow! support" ${HAVE_3DNOW} "NOT WIN32 AND NOT APPLE AND NOT WEB AND NOT ARM AND NOT URHO3D_SSE" FALSE)
    cmake_dependent_option (URHO3D_MMX "Enable MMX instruction set (32-bit Linux platform only); the MMX is effectively enabled when 3DNow! or SSE is enabled; should only be used for older CPU with MMX support" ${HAVE_MMX} "NOT WIN32 AND NOT APPLE AND NOT WEB AND NOT ARM AND NOT URHO3D_64BIT AND NOT URHO3D_SSE AND NOT URHO3D_3DNOW" FALSE)
    # For completeness sake - this option is intentionally not documented as we do not officially support PowerPC (yet)
    cmake_dependent_option (URHO3D_ALTIVEC "Enable AltiVec instruction set (PowerPC only)" ${HAVE_ALTIVEC} POWERPC FALSE)
    cmake_dependent_option (URHO3D_LUAJIT "Enable Lua scripting support using LuaJIT (check LuaJIT's CMakeLists.txt for more options)" FALSE "NOT WEB" FALSE)
    cmake_dependent_option (URHO3D_LUAJIT_AMALG "Enable LuaJIT amalgamated build (LuaJIT only)" FALSE URHO3D_LUAJIT FALSE)
    cmake_dependent_option (URHO3D_SAFE_LUA "Enable Lua C++ wrapper safety checks (Lua/LuaJIT only)" FALSE URHO3D_LUA FALSE)
    if (CMAKE_BUILD_TYPE STREQUAL Release OR CMAKE_CONFIGURATION_TYPES)
        set (URHO3D_DEFAULT_LUA_RAW FALSE)
    else ()
        set (URHO3D_DEFAULT_LUA_RAW TRUE)
    endif ()
    cmake_dependent_option (URHO3D_LUA_RAW_SCRIPT_LOADER "Prefer loading raw script files from the file system before falling back on Urho3D resource cache. Useful for debugging (e.g. breakpoints), but less performant (Lua/LuaJIT only)" ${URHO3D_DEFAULT_LUA_RAW} URHO3D_LUA FALSE)
    option (URHO3D_SAMPLES "Build sample applications" TRUE)
    option (URHO3D_UPDATE_SOURCE_TREE "Enable commands to copy back some of the generated build artifacts from build tree to source tree to facilitate devs to push them as part of a commit (for library devs with push right only)")
    option (URHO3D_BINDINGS "Enable API binding generation support for script subystems")
    cmake_dependent_option (URHO3D_CLANG_TOOLS "Build Clang tools (native on host system only)" FALSE "NOT ANDROID AND NOT ARM AND NOT WEB" FALSE)
    mark_as_advanced (URHO3D_UPDATE_SOURCE_TREE URHO3D_BINDINGS URHO3D_CLANG_TOOLS)
    cmake_dependent_option (URHO3D_TOOLS "Build tools (native, RPI, and ARM on Linux only)" TRUE "NOT IOS AND NOT ANDROID AND NOT WEB" FALSE)
    cmake_dependent_option (URHO3D_EXTRAS "Build extras (native, RPI, and ARM on Linux only)" FALSE "NOT IOS AND NOT ANDROID AND NOT WEB" FALSE)
    option (URHO3D_DOCS "Generate documentation as part of normal build")
    option (URHO3D_DOCS_QUIET "Generate documentation as part of normal build, suppress generation process from sending anything to stdout")
    option (URHO3D_PCH "Enable PCH support" TRUE)
    cmake_dependent_option (URHO3D_DATABASE_ODBC "Enable Database support with ODBC, requires vendor-specific ODBC driver" FALSE "NOT IOS AND NOT ANDROID AND NOT WEB;NOT MSVC OR NOT MSVC_VERSION VERSION_LESS 1900" FALSE)
    option (URHO3D_DATABASE_SQLITE "Enable Database support with SQLite embedded")
    # Enable file watcher support for automatic resource reloads by default.
    option (URHO3D_FILEWATCHER "Enable filewatcher support" TRUE)
    option (URHO3D_TESTING "Enable testing support")
    # By default this option is off (i.e. we use the MSVC dynamic runtime), this can be switched on if using Urho3D as a STATIC library
    cmake_dependent_option (URHO3D_STATIC_RUNTIME "Use static C/C++ runtime libraries and eliminate the need for runtime DLLs installation (VS only)" FALSE "MSVC" FALSE)
    if (((URHO3D_LUA AND NOT URHO3D_LUAJIT) OR URHO3D_DATABASE_SQLITE) AND NOT ANDROID AND NOT IOS AND NOT WEB AND NOT WIN32)
        # Find GNU Readline development library for Lua interpreter and SQLite's isql
        find_package (Readline)
    endif ()
    if (CPACK_SYSTEM_NAME STREQUAL Linux)
        cmake_dependent_option (URHO3D_USE_LIB64_RPM "Enable 64-bit RPM CPack generator using /usr/lib64 and disable all other generators (Debian-based host only)" FALSE "URHO3D_64BIT AND NOT HAS_LIB64" FALSE)
        cmake_dependent_option (URHO3D_USE_LIB_DEB "Enable 64-bit DEB CPack generator using /usr/lib and disable all other generators (Redhat-based host only)" FALSE "URHO3D_64BIT AND HAS_LIB64" FALSE)
    endif ()
    # Set to search in 'lib' or 'lib64' based on the chosen ABI
    if (NOT CMAKE_HOST_WIN32)
        set_property (GLOBAL PROPERTY FIND_LIBRARY_USE_LIB64_PATHS ${URHO3D_64BIT})
    endif ()
else ()
    set (URHO3D_LIB_TYPE "" CACHE STRING "Specify Urho3D library type, possible values are STATIC (default) and SHARED")
    set (URHO3D_HOME "" CACHE PATH "Path to Urho3D build tree or SDK installation location (downstream project only)")
    if (URHO3D_PCH OR URHO3D_UPDATE_SOURCE_TREE OR URHO3D_TOOLS)
        # Just reference it to suppress "unused variable" CMake warning on downstream projects using this CMake module
    endif ()
    if (CMAKE_PROJECT_NAME MATCHES ^Urho3D-ExternalProject-)
        set (URHO3D_SSE ${HAVE_SSE2})
    else ()
        # All Urho3D downstream projects require Urho3D library, so find Urho3D library here now
        find_package (Urho3D REQUIRED)
        include_directories (${URHO3D_INCLUDE_DIRS})
    endif ()
endif ()
option (URHO3D_PACKAGING "Enable resources packaging support, on Web platform default to 1, on other platforms default to 0" ${WEB})
# Enable profiling by default. If disabled, autoprofileblocks become no-ops and the Profiler subsystem is not instantiated.
option (URHO3D_PROFILING "Enable profiling support" TRUE)
# Enable logging by default. If disabled, LOGXXXX macros become no-ops and the Log subsystem is not instantiated.
option (URHO3D_LOGGING "Enable logging support" TRUE)
# Enable threading by default, except for Emscripten because its thread support is yet experimental
if (NOT WEB)
    set (THREADING_DEFAULT TRUE)
endif ()
option (URHO3D_THREADING "Enable thread support, on Web platform default to 0, on other platforms default to 1" ${THREADING_DEFAULT})
if (URHO3D_TESTING)
    if (WEB)
        set (DEFAULT_TIMEOUT 10)
        if (EMSCRIPTEN)
            set (EMSCRIPTEN_EMRUN_BROWSER firefox CACHE STRING "Specify the particular browser to be spawned by emrun during testing (Emscripten only), use 'emrun --list_browsers' command to get the list of possible values")
        endif ()
    else ()
        set (DEFAULT_TIMEOUT 5)
    endif ()
    set (URHO3D_TEST_TIMEOUT ${DEFAULT_TIMEOUT} CACHE STRING "Number of seconds to test run the executables (when testing support is enabled only), default to 10 on Web platform and 5 on other platforms")
else ()
    unset (URHO3D_TEST_TIMEOUT CACHE)
    if (EMSCRIPTEN_EMRUN_BROWSER)   # Suppress unused variable warning at the same time
        unset (EMSCRIPTEN_EMRUN_BROWSER CACHE)
    endif ()
endif ()
# Structured exception handling and minidumps on MSVC only
cmake_dependent_option (URHO3D_MINIDUMPS "Enable minidumps on crash (VS only)" TRUE "MSVC" FALSE)
# By default Windows platform setups main executable as Windows application with WinMain() as entry point
cmake_dependent_option (URHO3D_WIN32_CONSOLE "Use console main() instead of WinMain() as entry point when setting up Windows executable targets (Windows platform only)" FALSE "WIN32" FALSE)
cmake_dependent_option (URHO3D_MACOSX_BUNDLE "Use MACOSX_BUNDLE when setting up macOS executable targets (Xcode/macOS platform only)" FALSE "XCODE AND NOT IOS" FALSE)
if (CMAKE_CROSSCOMPILING AND NOT ANDROID AND NOT IOS)
    set (URHO3D_SCP_TO_TARGET "" CACHE STRING "Use scp to transfer executables to target system (non-Android cross-compiling build only), SSH digital key must be setup first for this to work, typical value has a pattern of usr@tgt:remote-loc")
else ()
    unset (URHO3D_SCP_TO_TARGET CACHE)
endif ()
if (ANDROID)
    set (ANDROID TRUE CACHE INTERNAL "Setup build for Android platform")
    cmake_dependent_option (ANDROID_NDK_GDB "Enable ndk-gdb for debugging (Android platform only)" FALSE "CMAKE_BUILD_TYPE STREQUAL Debug" FALSE)
else ()
    unset (ANDROID_NDK_GDB CACHE)
endif ()
if (MINGW AND CMAKE_CROSSCOMPILING)
    set (MINGW_PREFIX "" CACHE STRING "Prefix path to MinGW cross-compiler tools (MinGW cross-compiling build only)")
    set (MINGW_SYSROOT "" CACHE PATH "Path to MinGW system root (MinGW only); should only be used when the system root could not be auto-detected")
    # When cross-compiling then we are most probably in Unix-alike host environment which should not have problem to handle long include dirs
    # This change is required to keep ccache happy because it does not like the CMake generated include response file
    foreach (lang C CXX)
        foreach (cat OBJECTS INCLUDES)
            unset (CMAKE_${lang}_USE_RESPONSE_FILE_FOR_${cat})
        endforeach ()
    endforeach ()
endif ()
if (RPI)
    if (NOT RPI_SUPPORTED_ABIS)
        set (RPI_SUPPORTED_ABIS armeabi-v6)
        if (CMAKE_CROSSCOMPILING)
            # We have no way to know for sure so just give all the available options to user
            list (APPEND RPI_SUPPORTED_ABIS armeabi-v7a "armeabi-v7a with NEON" "armeabi-v7a with VFPV4")
        else ()
            # If not cross-compiling then we should be on the host system (device) itself, so below command is safe to be executed
            execute_process (COMMAND uname -m OUTPUT_VARIABLE HOST_MACHINE ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
            if (HOST_MACHINE MATCHES ^armv7)
                list (APPEND RPI_SUPPORTED_ABIS armeabi-v7a "armeabi-v7a with NEON" "armeabi-v7a with VFPV4")
                if (NOT RPI_ABI)
                    set (RPI_ABI armeabi-v7a)   # Set default to this specific target device
                endif ()
            endif ()
        endif ()
        set (RPI_SUPPORTED_ABIS ${RPI_SUPPORTED_ABIS} CACHE INTERNAL "Supported target ABIs for RPI build")
    endif ()
    if (CMAKE_CROSSCOMPILING)
        set (RPI_PREFIX "" CACHE STRING "Prefix path to Raspberry Pi cross-compiler tools (RPI cross-compiling build only)")
        set (RPI_SYSROOT "" CACHE PATH "Path to Raspberry Pi system root (RPI cross-compiling build only)")
    endif ()
    if (RPI_ABI)
        list (FIND RPI_SUPPORTED_ABIS ${RPI_ABI} RPI_ABI_FOUND_INDEX)
        if (RPI_ABI_FOUND_INDEX EQUAL -1)
            string (REPLACE ";" "\", \"" PRINTABLE_RPI_SUPPORTED_ABIS "${RPI_SUPPORTED_ABIS}")  # Stringify for string replace to work
            if (NOT CMAKE_CROSSCOMPILING)
                set (MSG_STR " by this Raspberry Pi device")
            endif ()
            message (FATAL_ERROR "Specified RPI_ABI = \"${RPI_ABI}\" is not supported${MSG_STR}. Supported values are: \"${PRINTABLE_RPI_SUPPORTED_ABIS}\".")
        endif()
    else ()
        set (RPI_ABI armeabi-v6)
    endif ()
    set (RPI_ABI ${RPI_ABI} CACHE STRING "Specify target ABI (RPI platform only), possible values are armeabi-v6 (default for RPI 1), armeabi-v7a (default for RPI 2), armeabi-v7a with NEON, and armeabi-v7a with VFPV4" FORCE)
endif ()
if (EMSCRIPTEN)     # CMAKE_CROSSCOMPILING is always true for Emscripten
    set (EMSCRIPTEN_ROOT_PATH "" CACHE PATH "Root path to Emscripten cross-compiler tools (Emscripten only)")
    set (EMSCRIPTEN_SYSROOT "" CACHE PATH "Path to Emscripten system root (Emscripten only)")
    option (EMSCRIPTEN_ALLOW_MEMORY_GROWTH "Enable memory growing based on application demand (Emscripten only)")
    math (EXPR EMSCRIPTEN_TOTAL_MEMORY "128 * 1024 * 1024")     # This option is ignored when EMSCRIPTEN_ALLOW_MEMORY_GROWTH option is set
    set (EMSCRIPTEN_TOTAL_MEMORY ${EMSCRIPTEN_TOTAL_MEMORY} CACHE STRING "Specify the total size of memory to be used (Emscripten only); default to 128 MB, this option is ignored when EMSCRIPTEN_ALLOW_MEMORY_GROWTH=1")
    set (EMSCRIPTEN_SHARE_DATA FALSE CACHE BOOL "Enable sharing data file support (Emscripten only)")
    set (EMSCRIPTEN_SYSTEM_LIBS "" CACHE STRING "Specify a semicolon-separated list of additional system libraries that should be pre-built using embuilder.py, by default 'dlmalloc', 'libc', 'libcxxabi', and 'gl' will be pre-built, so they should not be listed again (Emscripten only); when using CMake CLI on Unix-like host systems, the semicolon may need to be properly escaped; see usage of embuilder.py to get the full list of supported system libraries")
endif ()
# Constrain the build option values in cmake-gui, if applicable
set_property (CACHE URHO3D_LIB_TYPE PROPERTY STRINGS STATIC SHARED)
if (NOT CMAKE_CONFIGURATION_TYPES)
    set_property (CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS ${URHO3D_BUILD_CONFIGURATIONS})
endif ()
if (RPI)
    set_property (CACHE RPI_ABI PROPERTY STRINGS ${RPI_SUPPORTED_ABIS})
endif ()
# Handle mutually exclusive options and implied options
if (URHO3D_D3D11)
    set (URHO3D_OPENGL 0)
    unset (URHO3D_OPENGL CACHE)
endif ()
if (URHO3D_DATABASE_ODBC)
    set (URHO3D_DATABASE_SQLITE 0)
    unset (URHO3D_DATABASE_SQLITE CACHE)
endif ()
if (URHO3D_DATABASE_SQLITE OR URHO3D_DATABASE_ODBC)
    set (URHO3D_DATABASE 1)
endif ()
if (URHO3D_LUAJIT)
    set (JIT JIT)
    set (URHO3D_LUA 1)
endif ()

# Union all the sysroot variables into one so it can be referred to generically later
set (SYSROOT ${CMAKE_SYSROOT} ${MINGW_SYSROOT} ${IOS_SYSROOT} ${EMSCRIPTEN_SYSROOT} CACHE INTERNAL "Path to system root of the cross-compiling target")  # SYSROOT is empty for native build

# Clang tools building
if (URHO3D_CLANG_TOOLS OR URHO3D_BINDINGS)
    # Ensure LLVM/Clang is installed
    find_program (LLVM_CONFIG NAMES llvm-config llvm-config-64 llvm-config-32 HINTS $ENV{LLVM_CLANG_ROOT}/bin DOC "LLVM config tool" NO_CMAKE_FIND_ROOT_PATH)
    if (NOT LLVM_CONFIG)
        message (FATAL_ERROR "Could not find LLVM/Clang installation")
    endif ()
endif ()
if (URHO3D_CLANG_TOOLS)
    # Require C++11 standard and no precompiled-header
    set (URHO3D_C++11 1)
    set (URHO3D_PCH 0)
    set (URHO3D_LIB_TYPE SHARED)
    # Set build options that would maximise the AST of Urho3D library
    foreach (OPT
            URHO3D_ANGELSCRIPT
            URHO3D_DATABASE_SQLITE
            URHO3D_FILEWATCHER
            URHO3D_LOGGING
            URHO3D_LUA
            URHO3D_NAVIGATION
            URHO3D_NETWORK
            URHO3D_PHYSICS
            URHO3D_PROFILING
            URHO3D_URHO2D)
        set (${OPT} 1)
    endforeach()
    foreach (OPT URHO3D_TESTING URHO3D_LUAJIT URHO3D_DATABASE_ODBC)
        set (${OPT} 0)
    endforeach()
endif ()

# Enable testing
if (URHO3D_TESTING)
    enable_testing ()
endif ()

# Default library type is STATIC
if (URHO3D_LIB_TYPE)
    string (TOUPPER ${URHO3D_LIB_TYPE} URHO3D_LIB_TYPE)
endif ()
if (NOT URHO3D_LIB_TYPE STREQUAL SHARED)
    set (URHO3D_LIB_TYPE STATIC)
    if (MSVC)
        # This define will be baked into the export header for MSVC compiler
        set (URHO3D_STATIC_DEFINE 1)
    else ()
        # Only define it on the fly when necessary (both SHARED and STATIC libs can coexist) for other compiler toolchains
        add_definitions (-DURHO3D_STATIC_DEFINE)
    endif ()
endif ()

# Force C++11 standard (required by the generic bindings generation) if using AngelScript on Web and 64-bit ARM platforms
if (URHO3D_ANGELSCRIPT AND (EMSCRIPTEN OR (ARM AND URHO3D_64BIT)))
    set (URHO3D_C++11 1)
endif ()

# Force C++11 standard (required by nanodbc library) if using ODBC
if (URHO3D_DATABASE_ODBC)
    find_package (ODBC REQUIRED)
    set (URHO3D_C++11 1)
endif ()

# Define preprocessor macros (for building the Urho3D library) based on the configured build options
foreach (OPT
        URHO3D_ANGELSCRIPT
        URHO3D_DATABASE
        URHO3D_FILEWATCHER
        URHO3D_LOGGING
        URHO3D_LUA
        URHO3D_MINIDUMPS
        URHO3D_NAVIGATION
        URHO3D_NETWORK
        URHO3D_PHYSICS
        URHO3D_PROFILING
        URHO3D_THREADING
        URHO3D_URHO2D
        URHO3D_WIN32_CONSOLE)
    if (${OPT})
        add_definitions (-D${OPT})
    endif ()
endforeach ()

# TODO: The logic below is earmarked to be moved into SDL's CMakeLists.txt when refactoring the library dependency handling, until then ensure the DirectX package is not being searched again in external projects such as when building LuaJIT library
if (WIN32 AND NOT CMAKE_PROJECT_NAME MATCHES ^Urho3D-ExternalProject-)
    set (DIRECTX_REQUIRED_COMPONENTS)
    set (DIRECTX_OPTIONAL_COMPONENTS DInput DSound XAudio2 XInput)
    if (NOT URHO3D_OPENGL)
        if (URHO3D_D3D11)
            list (APPEND DIRECTX_REQUIRED_COMPONENTS D3D11)
        else ()
            list (APPEND DIRECTX_REQUIRED_COMPONENTS D3D)
        endif ()
    endif ()
    find_package (DirectX REQUIRED ${DIRECTX_REQUIRED_COMPONENTS} OPTIONAL_COMPONENTS ${DIRECTX_OPTIONAL_COMPONENTS})
    if (DIRECTX_FOUND)
        include_directories (SYSTEM ${DIRECTX_INCLUDE_DIRS})   # These variables may be empty when WinSDK or MinGW is being used
        link_directories (${DIRECTX_LIBRARY_DIRS})
    endif ()
endif ()

# Platform and compiler specific options
if (URHO3D_C++11)
    add_definitions (-DURHO3D_CXX11)   # Note the define is NOT 'URHO3D_C++11'!
    if (CMAKE_CXX_COMPILER_ID MATCHES GNU)
        # Use gnu++11/gnu++0x instead of c++11/c++0x as the latter does not work as expected when cross compiling
        if (VERIFIED_SUPPORTED_STANDARD)
            set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=${VERIFIED_SUPPORTED_STANDARD}")
        else ()
            foreach (STANDARD gnu++11 gnu++0x)  # Fallback to gnu++0x on older GCC version
                execute_process (COMMAND ${CMAKE_COMMAND} -E echo COMMAND ${CMAKE_CXX_COMPILER} -std=${STANDARD} -E - RESULT_VARIABLE GCC_EXIT_CODE OUTPUT_QUIET ERROR_QUIET)
                if (GCC_EXIT_CODE EQUAL 0)
                    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=${STANDARD}")
                    set (VERIFIED_SUPPORTED_STANDARD ${STANDARD} CACHE INTERNAL "GNU extension of C++11 standard that is verified to be supported by the chosen compiler")
                    break ()
                endif ()
            endforeach ()
            if (NOT GCC_EXIT_CODE EQUAL 0)
                message (FATAL_ERROR "Your GCC version ${COMPILER_VERSION} is too old to enable C++11 standard")
            endif ()
        endif ()
    elseif (CMAKE_CXX_COMPILER_ID MATCHES Clang)
        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")
    elseif (MSVC80)
        message (FATAL_ERROR "Your MSVC version is too told to enable C++11 standard")
    endif ()
endif ()
if (APPLE)
    if (IOS)
        # IOS-specific setup
        add_definitions (-DIOS)
        if (URHO3D_64BIT)
            if (DEFINED ENV{XCODE_64BIT_ONLY})                  # This environment variable is set automatically when ccache is just being cleared in Travis CI VM
                set (CMAKE_OSX_ARCHITECTURES "arm64 x86_64")    # This is a hack to temporarily only build 64-bit archs to reduce overall build time for one build
            else ()
                set (CMAKE_OSX_ARCHITECTURES $(ARCHS_STANDARD))
            endif ()
        else ()
            set (CMAKE_OSX_ARCHITECTURES $(ARCHS_STANDARD_32_BIT))
        endif ()
    else ()
        if (XCODE)
            # OSX-specific setup
            if (URHO3D_64BIT)
                if (DEFINED ENV{XCODE_64BIT_ONLY})
                    set (CMAKE_OSX_ARCHITECTURES x86_64)
                else ()
                    set (CMAKE_OSX_ARCHITECTURES $(ARCHS_STANDARD_32_64_BIT))
                endif ()
            else ()
                set (CMAKE_OSX_ARCHITECTURES $(ARCHS_STANDARD_32_BIT))
            endif ()
        endif ()
    endif ()
    # Common OSX and iOS bundle setup
    if (IOS OR URHO3D_MACOSX_BUNDLE)
        # Only set the bundle properties to its default when they are not explicitly specified by user
        if (NOT MACOSX_BUNDLE_GUI_IDENTIFIER)
            set (MACOSX_BUNDLE_GUI_IDENTIFIER com.github.urho3d.\${PRODUCT_NAME:rfc1034identifier:lower})
        endif ()
        if (NOT MACOSX_BUNDLE_BUNDLE_NAME)
            set (MACOSX_BUNDLE_BUNDLE_NAME \${PRODUCT_NAME})
        endif ()
    endif ()
endif ()
if (MSVC)
    # VS-specific setup
    add_definitions (-D_CRT_SECURE_NO_WARNINGS)
    if (URHO3D_STATIC_RUNTIME)
        set (RELEASE_RUNTIME /MT)
        set (DEBUG_RUNTIME /MTd)
    endif ()
    set (CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} ${DEBUG_RUNTIME}")
    set (CMAKE_C_FLAGS_RELWITHDEBINFO "${CMAKE_C_FLAGS_RELEASE} ${RELEASE_RUNTIME} /fp:fast /Zi /GS-")
    set (CMAKE_C_FLAGS_RELEASE ${CMAKE_C_FLAGS_RELWITHDEBINFO})
    set (CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} ${DEBUG_RUNTIME}")
    set (CMAKE_CXX_FLAGS_RELWITHDEBINFO "${CMAKE_CXX_FLAGS_RELEASE} ${RELEASE_RUNTIME} /fp:fast /Zi /GS- /D _SECURE_SCL=0")
    set (CMAKE_CXX_FLAGS_RELEASE ${CMAKE_CXX_FLAGS_RELWITHDEBINFO})
    # In Visual Studio, SSE2 flag is redundant if already compiling as 64bit; it is already the default for VS2012 (onward) on 32bit
    # Instead, we must turn SSE/SSE2 off explicitly if user really intends to turn it off
    if (URHO3D_SSE)
        if (NOT URHO3D_64BIT AND MSVC_VERSION LESS 1700)
            set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /arch:SSE2")
            set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /arch:SSE2")
        endif ()
    else ()
        set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /arch:IA32")
        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /arch:IA32")
    endif ()
    set (CMAKE_EXE_LINKER_FLAGS_RELWITHDEBINFO "${CMAKE_EXE_LINKER_FLAGS_RELEASE} /OPT:REF /OPT:ICF /DEBUG")
    set (CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} /OPT:REF /OPT:ICF")
else ()
    # GCC/Clang-specific setup
    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-invalid-offsetof")
    if (NOT ANDROID)    # Most of the flags are already setup in android.toolchain.cmake module
        if (ARM AND CMAKE_SYSTEM_NAME STREQUAL Linux)
            # Common compiler flags for aarch64-linux-gnu and arm-linux-gnueabihf, we do not support ARM on Windows for now
            set (ARM_CFLAGS "${ARM_CFLAGS} -fsigned-char -pipe")
            if (NOT URHO3D_64BIT)
                # We only support armhf distros, so turn on hard-float by default
                set (ARM_CFLAGS "${ARM_CFLAGS} -mfloat-abi=hard -Wno-psabi")
            endif ()
            # The configuration is done here instead of in CMake toolchain file because we also support native build which does not use toolchain file at all
            if (RPI)
                # RPI-specific setup
                add_definitions (-DRPI)
                if (RPI_ABI MATCHES ^armeabi-v7a)
                    set (ARM_CFLAGS "${ARM_CFLAGS} -mcpu=cortex-a7")
                    if (RPI_ABI MATCHES NEON)
                        set (ARM_CFLAGS "${ARM_CFLAGS} -mfpu=neon-vfpv4")
                    elseif (RPI_ABI MATCHES VFPV4)
                        set (ARM_CFLAGS "${ARM_CFLAGS} -mfpu=vfpv4")
                    else ()
                        set (ARM_CFLAGS "${ARM_CFLAGS} -mfpu=vfpv4-d16")
                    endif ()
                else ()
                    set (ARM_CFLAGS "${ARM_CFLAGS} -mcpu=arm1176jzf-s -mfpu=vfp")
                endif ()
            else ()
                # Generic ARM-specific setup
                add_definitions (-DGENERIC_ARM)
                if (URHO3D_64BIT)
                    # aarch64 has only one valid arch so far
                    set (ARM_CFLAGS "${ARM_CFLAGS} -march=armv8-a")
                elseif (URHO3D_ANGELSCRIPT)
                    # Angelscript seems to fail to compile using Thumb states, so force to use ARM states by default
                    set (ARM_CFLAGS "${ARM_CFLAGS} -marm")
                endif ()
                if (ARM_ABI_FLAGS)
                    # Instead of guessing all the possible ABIs, user would have to specify the ABI compiler flags explicitly via ARM_ABI_FLAGS build option
                    set (ARM_CFLAGS "${ARM_CFLAGS} ${ARM_ABI_FLAGS}")
                endif ()
            endif ()
            set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${ARM_CFLAGS}")
            set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${ARM_CFLAGS}")
        else ()
            if (URHO3D_SSE AND NOT XCODE AND NOT WEB)
                # This may influence the effective SSE level when URHO3D_SSE is on as well
                set (URHO3D_DEPLOYMENT_TARGET native CACHE STRING "Specify the minimum CPU type on which the target binaries are to be deployed (non-ARM platform only), see GCC/Clang's -march option for possible values; Use 'generic' for targeting a wide range of generic processors")
                if (NOT URHO3D_DEPLOYMENT_TARGET STREQUAL generic)
                    set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=${URHO3D_DEPLOYMENT_TARGET}")
                    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=${URHO3D_DEPLOYMENT_TARGET}")
                endif ()
            endif ()
            set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -ffast-math")
            set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffast-math")
            # We don't add these flags directly here for Xcode because we support Mach-O universal binary build
            # The compiler flags will be added later conditionally when the effective arch is i386 during build time (using XCODE_ATTRIBUTE target property)
            if (NOT XCODE)
                if (NOT URHO3D_64BIT)
                    # Not the compiler native ABI, this could only happen on multilib-capable compilers
                    if (NATIVE_64BIT)
                        set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -m32")
                        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -m32")
                    endif ()
                    # The effective SSE level could be higher, see also URHO3D_DEPLOYMENT_TARGET and CMAKE_OSX_DEPLOYMENT_TARGET build options
                    # The -mfpmath=sse is not set in global scope but it may be set in local scope when building LuaJIT sub-library for x86 arch
                    if (URHO3D_SSE)
                        set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -msse -msse2")
                        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -msse -msse2")
                    endif ()
                endif ()
                if (NOT URHO3D_SSE)
                    if (URHO3D_64BIT OR CMAKE_CXX_COMPILER_ID STREQUAL Clang)
                        # Clang enables SSE support for i386 ABI by default, so use the '-mno-sse' compiler flag to nullify that and make it consistent with GCC
                        set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mno-sse")
                        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mno-sse")
                    endif ()
                    if (URHO3D_MMX)
                        set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mmmx")
                        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mmmx")
                    endif()
                    if (URHO3D_3DNOW)
                        set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -m3dnow")
                        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -m3dnow")
                    endif ()
                endif ()
                # For completeness sake only as we do not support PowerPC (yet)
                if (URHO3D_ALTIVEC)
                    set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -maltivec")
                    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -maltivec")
                endif ()
            endif ()
        endif ()
        if (WEB)
            if (EMSCRIPTEN)
                # Emscripten-specific setup
                set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-warn-absolute-paths -Wno-unknown-warning-option")
                set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-warn-absolute-paths -Wno-unknown-warning-option")
                if (URHO3D_THREADING)
                    set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -s USE_PTHREADS=1")
                    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s USE_PTHREADS=1")
                endif ()
                # Prior to version 1.31.3 emcc does not consistently add the cpp standard and remove Emscripten-specific compiler flags
                # before passing on the work to the underlying LLVM/Clang compiler, this has resulted in preprocessing error when enabling the PCH and ccache
                # (See https://github.com/kripken/emscripten/issues/3365 for more detail)
                if (EMSCRIPTEN_EMCC_VERSION VERSION_LESS 1.31.3)
                    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++03")
                endif ()
                set (CMAKE_C_FLAGS_RELEASE "-Oz -DNDEBUG")
                set (CMAKE_CXX_FLAGS_RELEASE "-Oz -DNDEBUG")
                # Linker flags
                if (EMSCRIPTEN_ALLOW_MEMORY_GROWTH)
                    set (MEMORY_LINKER_FLAGS "-s ALLOW_MEMORY_GROWTH=1")
                else ()
                    set (MEMORY_LINKER_FLAGS "-s TOTAL_MEMORY=${EMSCRIPTEN_TOTAL_MEMORY}")
                endif ()
                set (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${MEMORY_LINKER_FLAGS} -s NO_EXIT_RUNTIME=1 -s ERROR_ON_UNDEFINED_SYMBOLS=1")
                set (CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} -O3 -s AGGRESSIVE_VARIABLE_ELIMINATION=1")     # Remove variables to make the -O3 regalloc easier
                set (CMAKE_EXE_LINKER_FLAGS_DEBUG "${CMAKE_EXE_LINKER_FLAGS_DEBUG} -g4")     # Preserve LLVM debug information, show line number debug comments, and generate source maps
                if (URHO3D_TESTING)
                    set (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} --emrun")  # Inject code into the generated Module object to enable capture of stdout, stderr and exit()
                endif ()
            endif ()
        elseif (MINGW)
            # MinGW-specific setup
            set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -static -static-libgcc -fno-keep-inline-dllexport")
            set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -static -static-libgcc -static-libstdc++ -fno-keep-inline-dllexport")
            if (NOT URHO3D_64BIT)
                # Prevent auto-vectorize optimization when using -O3, unless stack realign is being enforced globally
                if (URHO3D_SSE)
                    set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mstackrealign")
                    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mstackrealign")
                else ()
                    if (DEFINED ENV{TRAVIS})
                        # TODO: Remove this workaround when Travis CI VM has been migrated to Ubuntu 14.04 LTS
                        set (CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -fno-tree-slp-vectorize -fno-tree-vectorize")
                        set (CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -fno-tree-slp-vectorize -fno-tree-vectorize")
                    else ()
                        set (CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -fno-tree-loop-vectorize -fno-tree-slp-vectorize -fno-tree-vectorize")
                        set (CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -fno-tree-loop-vectorize -fno-tree-slp-vectorize -fno-tree-vectorize")
                    endif ()
                endif ()
            endif ()
        else ()
            # Not Android and not Emscripten and not MinGW derivative
            set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -pthread")     # This will emit '-DREENTRANT' to compiler and '-lpthread' to linker on Linux and Mac OSX platform
            set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread") # However, it may emit other equivalent compiler define and/or linker flag on other *nix platforms
        endif ()
        set (CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -DDEBUG -D_DEBUG")
        set (CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DDEBUG -D_DEBUG")
    endif ()
    if (CMAKE_CXX_COMPILER_ID STREQUAL Clang)
        # Clang-specific
        set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Qunused-arguments")
        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Qunused-arguments")
        if (NINJA OR "$ENV{USE_CCACHE}")    # Stringify to guard against undefined environment variable
            # When ccache support is on, these flags keep the color diagnostics pipe through ccache output and suppress Clang warning due ccache internal preprocessing step
            set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fcolor-diagnostics")
            set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fcolor-diagnostics")
        endif ()
        # Temporary workaround for Travis CI VM as Ubuntu 12.04 LTS still uses old glibc header files that do not have the necessary patch for Clang to work correctly
        # TODO: Remove this workaround when Travis CI VM has been migrated to Ubuntu 14.04 LTS
        if (DEFINED ENV{TRAVIS} AND "$ENV{LINUX}")
            add_definitions (-D__extern_always_inline=inline)
        endif ()
    else ()
        # GCC-specific
        if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER 4.9.1)
            set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fdiagnostics-color=auto")
            set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fdiagnostics-color=auto")
        endif ()
    endif ()
endif ()
# LuaJIT specific - extra linker flags for linking against LuaJIT (adapted from LuaJIT's original Makefile)
if (URHO3D_LUAJIT)
    if (URHO3D_64BIT AND APPLE AND NOT IOS)
        # 64-bit Mac OS X: it simply won't work without these flags; if you are reading this comment then you may want to know the following also
        # it's recommended to rebase all (self-compiled) shared libraries which are loaded at runtime on OSX/x64 (e.g. C extension modules for Lua), see: man rebase
        set (LUAJIT_EXE_LINKER_FLAGS_APPLE "-pagezero_size 10000 -image_base 100000000")
        set (LUAJIT_SHARED_LINKER_FLAGS_APPLE "-image_base 7fff04c4a000")
        if (NOT XCODE)
            set (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${LUAJIT_EXE_LINKER_FLAGS_APPLE}")
            set (CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${LUAJIT_SHARED_LINKER_FLAGS_APPLE}")
        endif ()
    elseif (URHO3D_LIB_TYPE STREQUAL STATIC AND NOT WIN32 AND NOT APPLE)    # The original condition also checks: AND NOT SunOS AND NOT PS3
        # We assume user may want to load C modules compiled for plain Lua with require(), so we have to ensure all the public symbols are exported when linking with Urho3D (and therefore LuaJIT) statically
        # Note: this implies that loading such modules on Windows platform may only work with SHARED library type
        set (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-E")
    endif ()
endif ()
# Trim the leading white space in the compiler/linker flags, if any
foreach (TYPE C CXX EXE_LINKER SHARED_LINKER)
    string (REGEX REPLACE "^ +" "" CMAKE_${TYPE}_FLAGS "${CMAKE_${TYPE}_FLAGS}")
endforeach ()

include (UrhoMacros)

# Set common project structure for all platforms
if (NOT DEST_RUNTIME_DIR)
    # Set common binary output directory if not already set (note that this module can be included in an external project which may already have DEST_RUNTIME_DIR preset)
    set_output_directories (${CMAKE_BINARY_DIR}/bin RUNTIME PDB)
endif ()
if (ANDROID)
    # Enable Android ndk-gdb
    if (ANDROID_NDK_GDB)
        set (NDK_GDB_SOLIB_PATH ${CMAKE_BINARY_DIR}/obj/local/${ANDROID_NDK_ABI_NAME}/)
        file (MAKE_DIRECTORY ${NDK_GDB_SOLIB_PATH})
        set (NDK_GDB_JNI ${CMAKE_BINARY_DIR}/jni)
        set (NDK_GDB_MK "# This is a generated file. DO NOT EDIT!\n\nAPP_ABI := ${ANDROID_NDK_ABI_NAME}\n")
        foreach (MK Android.mk Application.mk)
            if (NOT EXISTS ${NDK_GDB_JNI}/${MK})
                file (WRITE ${NDK_GDB_JNI}/${MK} ${NDK_GDB_MK})
            endif ()
        endforeach ()
        get_directory_property (INCLUDE_DIRECTORIES DIRECTORY ${PROJECT_SOURCE_DIR} INCLUDE_DIRECTORIES)
        string (REPLACE ";" " " INCLUDE_DIRECTORIES "${INCLUDE_DIRECTORIES}")   # Note: need to always "stringify" a variable in list context for replace to work correctly
        set (NDK_GDB_SETUP "# This is a generated file. DO NOT EDIT!\n\nset solib-search-path ${NDK_GDB_SOLIB_PATH}\ndirectory ${INCLUDE_DIRECTORIES}\n")
        file (WRITE ${ANDROID_LIBRARY_OUTPUT_PATH}/gdb.setup ${NDK_GDB_SETUP})
        file (COPY ${ANDROID_NDK}/prebuilt/android-${ANDROID_ARCH_NAME}/gdbserver/gdbserver DESTINATION ${ANDROID_LIBRARY_OUTPUT_PATH})
    else ()
        file (REMOVE ${ANDROID_LIBRARY_OUTPUT_PATH}/gdbserver)
    endif ()
    # Create symbolic links in the build tree
    file (MAKE_DIRECTORY ${CMAKE_SOURCE_DIR}/Android/assets)
    if (NOT URHO3D_PACKAGING)
        foreach (I CoreData Data)
            if (NOT EXISTS ${CMAKE_SOURCE_DIR}/Android/assets/${I})
                create_symlink (${CMAKE_SOURCE_DIR}/bin/${I} ${CMAKE_SOURCE_DIR}/Android/assets/${I} FALLBACK_TO_COPY)
            endif ()
        endforeach ()
    endif ()
    foreach (I AndroidManifest.xml build.xml custom_rules.xml project.properties src res assets jni)
        if (EXISTS ${CMAKE_SOURCE_DIR}/Android/${I} AND NOT EXISTS ${CMAKE_BINARY_DIR}/${I})    # No-ops when 'Android' is used as build tree
            create_symlink (${CMAKE_SOURCE_DIR}/Android/${I} ${CMAKE_BINARY_DIR}/${I} FALLBACK_TO_COPY)
        endif ()
    endforeach ()
elseif (WEB)
    # Create Urho3D custom HTML shell that also embeds our own project logo
    if (EMSCRIPTEN)
        if (NOT EXISTS ${CMAKE_BINARY_DIR}/Source/shell.html)
            file (READ ${EMSCRIPTEN_ROOT_PATH}/src/shell.html SHELL_HTML)
            string (REPLACE "<!doctype html>" "<!-- This is a generated file. DO NOT EDIT!-->\n\n<!doctype html>" SHELL_HTML "${SHELL_HTML}")     # Stringify to preserve semicolons
            string (REPLACE "<body>" "<body>\n\n<a href=\"https://urho3d.github.io\" title=\"Urho3D Homepage\"><img src=\"https://urho3d.github.io/assets/images/logo.png\" alt=\"link to https://urho3d.github.io\" height=\"80\" width=\"320\" /></a>\n" SHELL_HTML "${SHELL_HTML}")
            file (WRITE ${CMAKE_BINARY_DIR}/Source/shell.html "${SHELL_HTML}")
        endif ()
    endif ()
else ()
    # Ensure the output directory exist before creating the symlinks
    file (MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
    # Create symbolic links in the build tree
    foreach (I Autoload CoreData Data)
        if (NOT EXISTS ${CMAKE_BINARY_DIR}/bin/${I})
            create_symlink (${CMAKE_SOURCE_DIR}/bin/${I} ${CMAKE_BINARY_DIR}/bin/${I} FALLBACK_TO_COPY)
        endif ()
    endforeach ()
    # Warn user if PATH environment variable has not been correctly set for using ccache
    if (NOT CMAKE_CROSSCOMPILING AND NOT CMAKE_HOST_WIN32 AND "$ENV{USE_CCACHE}")
        if (APPLE)
            set (WHEREIS brew info ccache)
        else ()
            set (WHEREIS whereis -b ccache)
        endif ()
        execute_process (COMMAND ${WHEREIS} COMMAND grep -o \\S*lib\\S* RESULT_VARIABLE EXIT_CODE OUTPUT_VARIABLE CCACHE_SYMLINK ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
        if (EXIT_CODE EQUAL 0 AND NOT $ENV{PATH} MATCHES "${CCACHE_SYMLINK}")  # Need to stringify because CCACHE_SYMLINK variable could be empty when the command failed
            message (WARNING "The lib directory containing the ccache symlinks (${CCACHE_SYMLINK}) has not been added in the PATH environment variable. "
                "This is required to enable ccache support for native compiler toolchain. CMake has been configured to use the actual compiler toolchain instead of ccache. "
                "In order to rectify this, the build tree must be regenerated after the PATH environment variable has been adjusted accordingly.")
        endif ()
    endif ()
endif ()

# Post-CMake fixes
if (IOS)
    # TODO: can be removed when CMake minimum required has reached 3.4
    if (CMAKE_VERSION VERSION_LESS 3.4)
        # Due to a bug in the CMake/Xcode generator (fixed in 3.4) that prevents iOS targets (library and bundle) to be installed correctly
        # (see http://public.kitware.com/Bug/bug_relationship_graph.php?bug_id=12506&graph=dependency),
        # below temporary fix is required to work around the bug
        list (APPEND POST_CMAKE_FIXES COMMAND sed -i '' 's/EFFECTIVE_PLATFORM_NAME//g' ${CMAKE_BINARY_DIR}/CMakeScripts/install_postBuildPhase.make* || exit 0)
    endif ()
endif ()
if (POST_CMAKE_FIXES)
    add_custom_target (POST_CMAKE_FIXES ALL ${POST_CMAKE_FIXES} COMMENT "Applying post-cmake fixes")
endif ()
