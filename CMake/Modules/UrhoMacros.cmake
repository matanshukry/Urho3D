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

include (CMakeParseArguments)

# Macro for adjusting target output name by dropping _suffix from the target name
macro (adjust_target_name)
    if (TARGET_NAME MATCHES _.*$)
        string (REGEX REPLACE _.*$ "" OUTPUT_NAME ${TARGET_NAME})
        set_target_properties (${TARGET_NAME} PROPERTIES OUTPUT_NAME ${OUTPUT_NAME})
    endif ()
endmacro ()

# Macro for checking the SOURCE_FILES variable is properly initialized
macro (check_source_files)
    if (NOT SOURCE_FILES)
        message (FATAL_ERROR "Could not configure and generate the project file because no source files have been defined yet. "
            "You can define the source files explicitly by setting the SOURCE_FILES variable in your CMakeLists.txt; or "
            "by calling the define_source_files() macro which would by default glob all the C++ source files found in the same scope of "
            "CMakeLists.txt where the macro is being called and the macro would set the SOURCE_FILES variable automatically. "
            "If your source files are not located in the same directory as the CMakeLists.txt or your source files are "
            "more than just C++ language then you probably have to pass in extra arguments when calling the macro in order to make it works. "
            "See the define_source_files() macro definition in the CMake/Modules/UrhoCommon.cmake for more detail.")
    endif ()
endmacro ()

# Macro for setting symbolic link on platform that supports it
macro (create_symlink SOURCE DESTINATION)
    # Make absolute paths so they work more reliably on cmake-gui
    if (IS_ABSOLUTE ${SOURCE})
        set (ABS_SOURCE ${SOURCE})
    else ()
        set (ABS_SOURCE ${CMAKE_SOURCE_DIR}/${SOURCE})
    endif ()
    if (IS_ABSOLUTE ${DESTINATION})
        set (ABS_DESTINATION ${DESTINATION})
    else ()
        set (ABS_DESTINATION ${CMAKE_BINARY_DIR}/${DESTINATION})
    endif ()
    if (CMAKE_HOST_WIN32)
        if (IS_DIRECTORY ${ABS_SOURCE})
            set (SLASH_D /D)
        else ()
            unset (SLASH_D)
        endif ()
        if (HAS_MKLINK)
            if (NOT EXISTS ${ABS_DESTINATION})
                # Have to use string-REPLACE as file-TO_NATIVE_PATH does not work as expected with MinGW on "backward slash" host system
                string (REPLACE / \\ BACKWARD_ABS_DESTINATION ${ABS_DESTINATION})
                string (REPLACE / \\ BACKWARD_ABS_SOURCE ${ABS_SOURCE})
                execute_process (COMMAND cmd /C mklink ${SLASH_D} ${BACKWARD_ABS_DESTINATION} ${BACKWARD_ABS_SOURCE} OUTPUT_QUIET ERROR_QUIET)
            endif ()
        elseif (${ARGN} STREQUAL FALLBACK_TO_COPY)
            if (SLASH_D)
                set (COMMAND COMMAND ${CMAKE_COMMAND} -E copy_directory ${ABS_SOURCE} ${ABS_DESTINATION})
            else ()
                set (COMMAND COMMAND ${CMAKE_COMMAND} -E copy_if_different ${ABS_SOURCE} ${ABS_DESTINATION})
            endif ()
            # Fallback to copy only one time
            execute_process (${COMMAND})
            if (TARGET ${TARGET_NAME})
                # Fallback to copy every time the target is built
                add_custom_command (TARGET ${TARGET_NAME} POST_BUILD ${COMMAND})
            endif ()
        else ()
            message (WARNING "Unable to create symbolic link on this host system, you may need to manually copy file/dir from \"${SOURCE}\" to \"${DESTINATION}\"")
        endif ()
    else ()
        execute_process (COMMAND ${CMAKE_COMMAND} -E create_symlink ${ABS_SOURCE} ${ABS_DESTINATION})
    endif ()
endmacro ()

# *** THIS IS A DEPRECATED MACRO ***
# Macro for defining external library dependencies
# The purpose of this macro is emulate CMake to set the external library dependencies transitively
# It works for both targets setup within Urho3D project and downstream projects that uses Urho3D as external static/shared library
# *** THIS IS A DEPRECATED MACRO ***
macro (define_dependency_libs TARGET)
    # ThirdParty/SDL external dependency
    if (${TARGET} MATCHES SDL|Urho3D)
        if (WIN32)
            list (APPEND LIBS user32 gdi32 winmm imm32 ole32 oleaut32 version uuid)
        elseif (APPLE)
            list (APPEND LIBS iconv)
        elseif (ANDROID)
            list (APPEND LIBS dl log android)
        else ()
            # Linux
            if (NOT WEB)
                list (APPEND LIBS dl m rt)
            endif ()
            if (RPI)
                list (APPEND ABSOLUTE_PATH_LIBS ${VIDEOCORE_LIBRARIES})
            endif ()
        endif ()
    endif ()

    # ThirdParty/kNet & ThirdParty/Civetweb external dependency
    if (${TARGET} MATCHES Civetweb|kNet|Urho3D)
        if (WIN32)
            list (APPEND LIBS ws2_32)
        endif ()
    endif ()

    # Urho3D/LuaJIT external dependency
    if (URHO3D_LUAJIT AND ${TARGET} MATCHES LuaJIT|Urho3D)
        if (NOT WIN32 AND NOT WEB)
            list (APPEND LIBS dl m)
        endif ()
    endif ()

    # Urho3D external dependency
    if (${TARGET} STREQUAL Urho3D)
        # Core
        if (WIN32)
            list (APPEND LIBS winmm)
            if (URHO3D_MINIDUMPS)
                list (APPEND LIBS dbghelp)
            endif ()
        elseif (APPLE)
            if (IOS OR TVOS)
                list (APPEND LIBS "-framework AudioToolbox" "-framework CoreAudio" "-framework CoreGraphics" "-framework CoreMotion" "-framework Foundation" "-framework GameController" "-framework OpenGLES" "-framework QuartzCore" "-framework UIKit")
            else ()
                list (APPEND LIBS "-framework AudioUnit" "-framework Carbon" "-framework Cocoa" "-framework CoreAudio" "-framework CoreServices" "-framework CoreVideo" "-framework ForceFeedback" "-framework IOKit" "-framework OpenGL")
            endif ()
        endif ()

        # Graphics
        if (URHO3D_OPENGL)
            if (APPLE)
                # Do nothing
            elseif (WIN32)
                list (APPEND LIBS opengl32)
            elseif (ANDROID OR ARM)
                list (APPEND LIBS GLESv1_CM GLESv2)
            else ()
                list (APPEND LIBS GL)
            endif ()
        elseif (DIRECT3D_LIBRARIES)
            list (APPEND LIBS ${DIRECT3D_LIBRARIES})
        endif ()

        # Database
        if (URHO3D_DATABASE_ODBC)
            list (APPEND LIBS ${ODBC_LIBRARIES})
        endif ()

        # This variable value can either be 'Urho3D' target or an absolute path to an actual static/shared Urho3D library or empty (if we are building the library itself)
        # The former would cause CMake not only to link against the Urho3D library but also to add a dependency to Urho3D target
        if (URHO3D_LIBRARIES)
            if (WIN32 AND URHO3D_LIBRARIES_DBG AND URHO3D_LIBRARIES_REL AND TARGET ${TARGET_NAME})
                # Special handling when both debug and release libraries are found
                target_link_libraries (${TARGET_NAME} debug ${URHO3D_LIBRARIES_DBG} optimized ${URHO3D_LIBRARIES_REL})
            else ()
                if (TARGET ${TARGET}_universal)
                    add_dependencies (${TARGET_NAME} ${TARGET}_universal)
                endif ()
                list (APPEND ABSOLUTE_PATH_LIBS ${URHO3D_LIBRARIES})
            endif ()
        endif ()
    endif ()
endmacro ()

# Macro for defining source files with optional arguments as follows:
#  GLOB_CPP_PATTERNS <list> - Use the provided globbing patterns for CPP_FILES instead of the default *.cpp
#  GLOB_H_PATTERNS <list> - Use the provided globbing patterns for H_FILES instead of the default *.h
#  EXCLUDE_PATTERNS <list> - Use the provided patterns for excluding matched source files
#  EXTRA_CPP_FILES <list> - Include the provided list of files into CPP_FILES result
#  EXTRA_H_FILES <list> - Include the provided list of files into H_FILES result
#  PCH <list> - Enable precompiled header support on the defined source files using the specified header file, the list is "<path/to/header> [C++|C]"
#  PARENT_SCOPE - Glob source files in current directory but set the result in parent-scope's variable ${DIR}_CPP_FILES and ${DIR}_H_FILES instead
#  RECURSE - Option to glob recursively
#  GROUP - Option to group source files based on its relative path to the corresponding parent directory (only works when PARENT_SCOPE option is not in use)
macro (define_source_files)
    # Source files are defined by globbing source files in current source directory and also by including the extra source files if provided
    cmake_parse_arguments (ARG "PARENT_SCOPE;RECURSE;GROUP" "" "PCH;EXTRA_CPP_FILES;EXTRA_H_FILES;GLOB_CPP_PATTERNS;GLOB_H_PATTERNS;EXCLUDE_PATTERNS" ${ARGN})
    if (NOT ARG_GLOB_CPP_PATTERNS)
        set (ARG_GLOB_CPP_PATTERNS *.cpp)    # Default glob pattern
    endif ()
    if (NOT ARG_GLOB_H_PATTERNS)
        set (ARG_GLOB_H_PATTERNS *.h)
    endif ()
    if (ARG_RECURSE)
        set (ARG_RECURSE _RECURSE)
    else ()
        unset (ARG_RECURSE)
    endif ()
    file (GLOB${ARG_RECURSE} CPP_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} ${ARG_GLOB_CPP_PATTERNS})
    file (GLOB${ARG_RECURSE} H_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} ${ARG_GLOB_H_PATTERNS})
    if (ARG_EXCLUDE_PATTERNS)
        set (CPP_FILES_WITH_SENTINEL ";${CPP_FILES};")  # Stringify the lists
        set (H_FILES_WITH_SENTINEL ";${H_FILES};")
        foreach (PATTERN ${ARG_EXCLUDE_PATTERNS})
            foreach (LOOP RANGE 1)
                string (REGEX REPLACE ";${PATTERN};" ";;" CPP_FILES_WITH_SENTINEL "${CPP_FILES_WITH_SENTINEL}")
                string (REGEX REPLACE ";${PATTERN};" ";;" H_FILES_WITH_SENTINEL "${H_FILES_WITH_SENTINEL}")
            endforeach ()
        endforeach ()
        set (CPP_FILES ${CPP_FILES_WITH_SENTINEL})      # Convert strings back to lists, extra sentinels are harmless
        set (H_FILES ${H_FILES_WITH_SENTINEL})
    endif ()
    list (APPEND CPP_FILES ${ARG_EXTRA_CPP_FILES})
    list (APPEND H_FILES ${ARG_EXTRA_H_FILES})
    set (SOURCE_FILES ${CPP_FILES} ${H_FILES})

    # Optionally enable PCH
    if (ARG_PCH)
        enable_pch (${ARG_PCH})
    endif ()

    # Optionally accumulate source files at parent scope
    if (ARG_PARENT_SCOPE)
        get_filename_component (NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
        set (${NAME}_CPP_FILES ${CPP_FILES} PARENT_SCOPE)
        set (${NAME}_H_FILES ${H_FILES} PARENT_SCOPE)
    # Optionally put source files into further sub-group (only works when PARENT_SCOPE option is not in use)
    elseif (ARG_GROUP)
        foreach (CPP_FILE ${CPP_FILES})
            get_filename_component (PATH ${CPP_FILE} PATH)
            if (PATH)
                string (REPLACE / \\ PATH ${PATH})
                source_group ("Source Files\\${PATH}" FILES ${CPP_FILE})
            endif ()
        endforeach ()
        foreach (H_FILE ${H_FILES})
            get_filename_component (PATH ${H_FILE} PATH)
            if (PATH)
                string (REPLACE / \\ PATH ${PATH})
                source_group ("Header Files\\${PATH}" FILES ${H_FILE})
            endif ()
        endforeach ()
    endif ()
endmacro ()

include (GenerateExportHeader)

# Macro for precompiling header (On MSVC, the dummy C++ or C implementation file for precompiling the header file would be generated if not already exists)
# This macro should be called before the CMake target has been added
# Typically, user should indirectly call this macro by using the 'PCH' option when calling define_source_files() macro
macro (enable_pch HEADER_PATHNAME)
    # No op when PCH support is not enabled
    if (URHO3D_PCH)
        # Get the optional LANG parameter to indicate whether the header should be treated as C or C++ header, default to C++
        if ("${ARGN}" STREQUAL C)   # Stringify as the LANG paramater could be empty
            set (EXT c)
            set (LANG C)
            set (LANG_H c-header)
        else ()
            # This is the default
            set (EXT cpp)
            set (LANG CXX)
            set (LANG_H c++-header)
        endif ()
        # Relative path is resolved using CMAKE_CURRENT_SOURCE_DIR
        if (IS_ABSOLUTE ${HEADER_PATHNAME})
            set (ABS_HEADER_PATHNAME ${HEADER_PATHNAME})
        else ()
            set (ABS_HEADER_PATHNAME ${CMAKE_CURRENT_SOURCE_DIR}/${HEADER_PATHNAME})
        endif ()
        # Determine the precompiled header output filename
        get_filename_component (HEADER_FILENAME ${HEADER_PATHNAME} NAME)
        if (CMAKE_COMPILER_IS_GNUCXX)
            # GNU g++
            set (PCH_FILENAME ${HEADER_FILENAME}.gch)
        else ()
            # Clang or MSVC
            set (PCH_FILENAME ${HEADER_FILENAME}.pch)
        endif ()

        if (MSVC)
            get_filename_component (NAME_WE ${HEADER_FILENAME} NAME_WE)
            if (TARGET ${TARGET_NAME})
                if (VS)
                    # VS is multi-config, the exact path is only known during actual build time based on effective build config
                    set (PCH_PATHNAME "$(IntDir)${PCH_FILENAME}")
                else ()
                    set (PCH_PATHNAME ${CMAKE_CURRENT_BINARY_DIR}/${PCH_FILENAME})
                endif ()
                foreach (FILE ${SOURCE_FILES})
                    if (FILE MATCHES \\.${EXT}$)
                        if (FILE MATCHES ${NAME_WE}\\.${EXT}$)
                            # Precompiling header file
                            set_property (SOURCE ${FILE} APPEND_STRING PROPERTY COMPILE_FLAGS " /Fp${PCH_PATHNAME} /Yc${HEADER_FILENAME}")     # Need a leading space for appending
                        else ()
                            # Using precompiled header file
                            set_property (SOURCE ${FILE} APPEND_STRING PROPERTY COMPILE_FLAGS " /Fp${PCH_PATHNAME} /Yu${HEADER_FILENAME} /FI${HEADER_FILENAME}")
                        endif ()
                    endif ()
                endforeach ()
                unset (${TARGET_NAME}_HEADER_PATHNAME)
            else ()
                # The target has not been created yet, so set an internal variable to come back here again later
                set (${TARGET_NAME}_HEADER_PATHNAME ${ARGV})
                # But proceed to add the dummy C++ or C implementation file if necessary
                set (${LANG}_FILENAME ${NAME_WE}.${EXT})
                get_filename_component (PATH ${HEADER_PATHNAME} PATH)
                if (PATH)
                    set (PATH ${PATH}/)
                endif ()
                list (FIND SOURCE_FILES ${PATH}${${LANG}_FILENAME} ${LANG}_FILENAME_FOUND)
                if (${LANG}_FILENAME_FOUND STREQUAL -1)
                    if (NOT EXISTS ${CMAKE_CURRENT_BINARY_DIR}/${${LANG}_FILENAME})
                        # Only generate it once so that its timestamp is not touched unnecessarily
                        file (WRITE ${CMAKE_CURRENT_BINARY_DIR}/${${LANG}_FILENAME} "// This is a generated file. DO NOT EDIT!\n\n#include \"${HEADER_FILENAME}\"")
                    endif ()
                    list (INSERT SOURCE_FILES 0 ${${LANG}_FILENAME})
                endif ()
            endif ()
        elseif (XCODE)
            if (TARGET ${TARGET_NAME})
                # Precompiling and using precompiled header file
                set_target_properties (${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_GCC_PRECOMPILE_PREFIX_HEADER YES XCODE_ATTRIBUTE_GCC_PREFIX_HEADER ${ABS_HEADER_PATHNAME})
                unset (${TARGET_NAME}_HEADER_PATHNAME)
            else ()
                # The target has not been created yet, so set an internal variable to come back here again later
                set (${TARGET_NAME}_HEADER_PATHNAME ${ARGV})
            endif ()
        else ()
            # GCC or Clang
            if (TARGET ${TARGET_NAME})
                # Precompiling header file
                get_directory_property (COMPILE_DEFINITIONS COMPILE_DEFINITIONS)
                get_directory_property (INCLUDE_DIRECTORIES INCLUDE_DIRECTORIES)
                get_target_property (TYPE ${TARGET_NAME} TYPE)
                if (TYPE MATCHES SHARED)
                    list (APPEND COMPILE_DEFINITIONS ${TARGET_NAME}_EXPORTS)
                    # todo: Reevaluate the replacement of this deprecated function (since CMake 2.8.12) when the CMake minimum required version is set to 2.8.12
                    # At the moment it seems using the function is the "only way" to get the export flags into a CMake variable
                    # Additionally, CMake implementation of 'VISIBILITY_INLINES_HIDDEN' has a bug (tested in 2.8.12.2) that it erroneously sets the flag for C compiler too
                    add_compiler_export_flags (COMPILER_EXPORT_FLAGS)
                    # To cater for MinGW which already uses PIC for all codes
                    if (NOT MINGW)
                        set (COMPILER_EXPORT_FLAGS "${COMPILER_EXPORT_FLAGS} -fPIC")
                    endif ()
                elseif (PROJECT_NAME STREQUAL Urho3D AND NOT ${TARGET_NAME} STREQUAL Urho3D AND URHO3D_LIB_TYPE STREQUAL SHARED)
                    # If it is one of the Urho3D library dependency then use the same PIC flag as Urho3D library
                    if (NOT MINGW)
                        set (COMPILER_EXPORT_FLAGS -fPIC)
                    endif ()
                endif ()
                string (REPLACE ";" " -D" COMPILE_DEFINITIONS "-D${COMPILE_DEFINITIONS}")
                string (REPLACE "\"" "\\\"" COMPILE_DEFINITIONS ${COMPILE_DEFINITIONS})
                string (REPLACE ";" "\" -I\"" INCLUDE_DIRECTORIES "-I\"${INCLUDE_DIRECTORIES}\"")
                if (CMAKE_SYSROOT)
                    set (SYSROOT_FLAGS "--sysroot=\"${CMAKE_SYSROOT}\"")
                endif ()
                # Make sure the precompiled headers are not stale by creating custom rules to re-compile the header as necessary
                file (MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PCH_FILENAME})
                foreach (CONFIG ${CMAKE_CONFIGURATION_TYPES} ${CMAKE_BUILD_TYPE})   # These two vars are mutually exclusive
                    # Generate *.rsp containing configuration specific compiler flags
                    string (TOUPPER ${CONFIG} UPPERCASE_CONFIG)
                    file (WRITE ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME}.${CONFIG}.pch.rsp.new "${COMPILE_DEFINITIONS} ${SYSROOT_FLAGS} ${CLANG_${LANG}_FLAGS} ${CMAKE_${LANG}_FLAGS} ${CMAKE_${LANG}_FLAGS_${UPPERCASE_CONFIG}} ${COMPILER_EXPORT_FLAGS} ${INCLUDE_DIRECTORIES} -c -x ${LANG_H}")
                    execute_process (COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME}.${CONFIG}.pch.rsp.new ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME}.${CONFIG}.pch.rsp)
                    file (REMOVE ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME}.${CONFIG}.pch.rsp.new)
                    # Determine the dependency list
                    execute_process (COMMAND ${CMAKE_${LANG}_COMPILER} @${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME}.${CONFIG}.pch.rsp -MTdeps -MM -o ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME}.${CONFIG}.pch.deps ${ABS_HEADER_PATHNAME} RESULT_VARIABLE ${LANG}_COMPILER_EXIT_CODE)
                    if (NOT ${LANG}_COMPILER_EXIT_CODE EQUAL 0)
                        message (FATAL_ERROR
                            "The configured compiler toolchain in the build tree is not able to handle all the compiler flags required to build the project with PCH enabled. "
                            "Please kindly update your compiler toolchain to its latest version. "
                            "If you are using MinGW then make sure it is MinGW-W64 instead of MinGW-W32 or TDM-GCC (Code::Blocks default). "
                            "Or disable the PCH build support by passing the '-DURHO3D_PCH=0' when retrying to configure/generate the build tree. "
                            "However, if you think there is something wrong with our build system then kindly file a bug report to the project devs.")
                    endif ()
                    file (STRINGS ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME}.${CONFIG}.pch.deps DEPS)
                    string (REGEX REPLACE "^deps: *| *\\; *" ";" DEPS ${DEPS})
                    string (REGEX REPLACE "\\\\ " "\ " DEPS "${DEPS}")  # Need to stringify the second time to preserve the semicolons
                    # Create the rule that depends on the included headers
                    add_custom_command (OUTPUT ${HEADER_FILENAME}.${CONFIG}.pch.trigger
                        COMMAND ${CMAKE_${LANG}_COMPILER} @${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME}.${CONFIG}.pch.rsp -o ${PCH_FILENAME}/${PCH_FILENAME}.${CONFIG} ${ABS_HEADER_PATHNAME}
                        COMMAND ${CMAKE_COMMAND} -E touch ${HEADER_FILENAME}.${CONFIG}.pch.trigger
                        DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME}.${CONFIG}.pch.rsp ${DEPS}
                        COMMENT "Precompiling header file '${HEADER_FILENAME}' for ${CONFIG} configuration")
                endforeach ()
                # Using precompiled header file
                if ($ENV{COVERITY_SCAN_BRANCH})
                    # Coverity scan does not support PCH so workaround by including the actual header file
                    set (ABS_PATH_PCH ${ABS_HEADER_PATHNAME})
                else ()
                    set (ABS_PATH_PCH ${CMAKE_CURRENT_BINARY_DIR}/${HEADER_FILENAME})
                endif ()
                set (CMAKE_${LANG}_FLAGS "${CMAKE_${LANG}_FLAGS} -include \"${ABS_PATH_PCH}\"")
                unset (${TARGET_NAME}_HEADER_PATHNAME)
            else ()
                # The target has not been created yet, so set an internal variable to come back here again later
                set (${TARGET_NAME}_HEADER_PATHNAME ${ARGV})
                # But proceed to add the dummy source file(s) to trigger the custom command output rule
                if (CMAKE_CONFIGURATION_TYPES)
                    # Multi-config, trigger all rules and let the compiler to choose which precompiled header is suitable to use
                    foreach (CONFIG ${CMAKE_CONFIGURATION_TYPES})
                        list (APPEND TRIGGERS ${HEADER_FILENAME}.${CONFIG}.pch.trigger)
                    endforeach ()
                else ()
                    # Single-config, just trigger the corresponding rule matching the current build configuration
                    set (TRIGGERS ${HEADER_FILENAME}.${CMAKE_BUILD_TYPE}.pch.trigger)
                endif ()
                list (APPEND SOURCE_FILES ${TRIGGERS})
            endif ()
        endif ()
    endif ()
endmacro ()

# Macro for finding file in Urho3D build tree or Urho3D SDK
macro (find_Urho3D_file VAR NAME)
    # Pass the arguments to the actual find command
    cmake_parse_arguments (ARG "" "DOC;MSG_MODE" "HINTS;PATHS;PATH_SUFFIXES" ${ARGN})
    find_file (${VAR} ${NAME} HINTS ${ARG_HINTS} PATHS ${ARG_PATHS} PATH_SUFFIXES ${ARG_PATH_SUFFIXES} DOC ${ARG_DOC} NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
    mark_as_advanced (${VAR})  # Hide it from cmake-gui in non-advanced mode
    if (NOT ${VAR} AND ARG_MSG_MODE)
        message (${ARG_MSG_MODE}
            "Could not find ${VAR} file in the Urho3D build tree or Urho3D SDK. "
            "Please reconfigure and rebuild your Urho3D build tree or reinstall the SDK for the correct target platform.")
    endif ()
endmacro ()

# Macro for finding tool in Urho3D build tree or Urho3D SDK
macro (find_Urho3D_tool VAR NAME)
    # Pass the arguments to the actual find command
    cmake_parse_arguments (ARG "" "DOC;MSG_MODE" "HINTS;PATHS;PATH_SUFFIXES" ${ARGN})
    find_program (${VAR} ${NAME} HINTS ${ARG_HINTS} PATHS ${ARG_PATHS} PATH_SUFFIXES ${ARG_PATH_SUFFIXES} DOC ${ARG_DOC} NO_DEFAULT_PATH)
    mark_as_advanced (${VAR})  # Hide it from cmake-gui in non-advanced mode
    if (NOT ${VAR})
        set (${VAR} ${CMAKE_BINARY_DIR}/bin/tool/${NAME})
        if (ARG_MSG_MODE AND NOT CMAKE_PROJECT_NAME STREQUAL Urho3D)
            message (${ARG_MSG_MODE}
                "Could not find ${VAR} tool in the Urho3D build tree or Urho3D SDK. Your project may not build successfully without this tool. "
                "You may have to first rebuild the Urho3D in its build tree or reinstall Urho3D SDK to get this tool built or installed properly. "
                "Alternatively, copy the ${VAR} executable manually into bin/tool subdirectory in your own project build tree.")
        endif ()
    endif ()
endmacro ()

# Macro for setting up header files installation for the SDK and the build tree (only support subset of install command arguments)
#  FILES <list> - File list to be installed
#  DIRECTORY <list> - Directory list to be installed
#  FILES_MATCHING - Option to perform file pattern matching on DIRECTORY list
#  USE_FILE_SYMLINK - Option to use file symlinks on the matched files found in the DIRECTORY list
#  BUILD_TREE_ONLY - Option to install the header files into the build tree only
#  PATTERN <list> - Pattern list to be used in file pattern matching option
#  BASE <value> - An absolute base path to be prepended to the destination path when installing to build tree, default to build tree
#  DESTINATION <value> - A relative destination path to be installed to
#  ACCUMULATE <value> - Accumulate the header files into the specified CMake variable, implies USE_FILE_SYMLINK when input list is a directory
macro (install_header_files)
    # Need to check if the destination variable is defined first because this macro could be called by downstream project that does not wish to install anything
    if (DEST_INCLUDE_DIR)
        # Parse the arguments for the underlying install command for the SDK
        cmake_parse_arguments (ARG "FILES_MATCHING;USE_FILE_SYMLINK;BUILD_TREE_ONLY" "BASE;DESTINATION;ACCUMULATE" "FILES;DIRECTORY;PATTERN" ${ARGN})
        unset (INSTALL_MATCHING)
        if (ARG_FILES)
            set (INSTALL_TYPE FILES)
            set (INSTALL_SOURCES ${ARG_FILES})
        elseif (ARG_DIRECTORY)
            set (INSTALL_TYPE DIRECTORY)
            set (INSTALL_SOURCES ${ARG_DIRECTORY})
            if (ARG_FILES_MATCHING)
                set (INSTALL_MATCHING FILES_MATCHING)
                # Our macro supports PATTERN <list> but CMake's install command does not, so convert the list to: PATTERN <value1> PATTERN <value2> ...
                foreach (PATTERN ${ARG_PATTERN})
                    list (APPEND INSTALL_MATCHING PATTERN ${PATTERN})
                endforeach ()
            endif ()
        else ()
            message (FATAL_ERROR "Couldn't setup install command because the install type is not specified.")
        endif ()
        if (NOT ARG_DESTINATION)
            message (FATAL_ERROR "Couldn't setup install command because the install destination is not specified.")
        endif ()
        if (NOT ARG_BUILD_TREE_ONLY AND NOT CMAKE_PROJECT_NAME MATCHES ^Urho3D-ExternalProject-)
            install (${INSTALL_TYPE} ${INSTALL_SOURCES} DESTINATION ${ARG_DESTINATION} ${INSTALL_MATCHING})
        endif ()

        # Reparse the arguments for the create_symlink macro to "install" the header files in the build tree
        if (NOT ARG_BASE)
            set (ARG_BASE ${CMAKE_BINARY_DIR})  # Use build tree as base path
        endif ()
        foreach (INSTALL_SOURCE ${INSTALL_SOURCES})
            if (NOT IS_ABSOLUTE ${INSTALL_SOURCE})
                set (INSTALL_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/${INSTALL_SOURCE})
            endif ()
            if (INSTALL_SOURCE MATCHES /$)
                # Source is a directory
                if (ARG_USE_FILE_SYMLINK OR ARG_ACCUMULATE OR BASH_ON_WINDOWS)
                    # Use file symlink for each individual files in the source directory
                    if (IS_SYMLINK ${ARG_DESTINATION} AND NOT CMAKE_HOST_WIN32)
                        execute_process (COMMAND ${CMAKE_COMMAND} -E remove ${ARG_DESTINATION})
                    endif ()
                    set (GLOBBING_EXPRESSION RELATIVE ${INSTALL_SOURCE})
                    if (ARG_FILES_MATCHING)
                        foreach (PATTERN ${ARG_PATTERN})
                            list (APPEND GLOBBING_EXPRESSION ${INSTALL_SOURCE}${PATTERN})
                        endforeach ()
                    else ()
                        list (APPEND GLOBBING_EXPRESSION ${INSTALL_SOURCE}*)
                    endif ()
                    file (GLOB_RECURSE NAMES ${GLOBBING_EXPRESSION})
                    foreach (NAME ${NAMES})
                        get_filename_component (PATH ${ARG_DESTINATION}/${NAME} PATH)
                        # Recreate the source directory structure in the destination path
                        if (NOT EXISTS ${ARG_BASE}/${PATH})
                            file (MAKE_DIRECTORY ${ARG_BASE}/${PATH})
                        endif ()
                        create_symlink (${INSTALL_SOURCE}${NAME} ${ARG_DESTINATION}/${NAME} FALLBACK_TO_COPY)
                        if (ARG_ACCUMULATE)
                            list (APPEND ${ARG_ACCUMULATE} ${ARG_DESTINATION}/${NAME})
                        endif ()
                    endforeach ()
                else ()
                    # Use a single symlink pointing to the source directory
                    if (NOT IS_SYMLINK ${ARG_DESTINATION} AND NOT CMAKE_HOST_WIN32)
                        execute_process (COMMAND ${CMAKE_COMMAND} -E remove_directory ${ARG_DESTINATION})
                    endif ()
                    create_symlink (${INSTALL_SOURCE} ${ARG_DESTINATION} FALLBACK_TO_COPY)
                endif ()
            else ()
                # Source is a file (it could also be actually a directory to be treated as a "file", i.e. for creating symlink pointing to the directory)
                get_filename_component (NAME ${INSTALL_SOURCE} NAME)
                create_symlink (${INSTALL_SOURCE} ${ARG_DESTINATION}/${NAME} FALLBACK_TO_COPY)
                if (ARG_ACCUMULATE)
                    list (APPEND ${ARG_ACCUMULATE} ${ARG_DESTINATION}/${NAME})
                endif ()
            endif ()
        endforeach ()
    endif ()
endmacro ()

# Macro for setting common output directories
macro (set_output_directories OUTPUT_PATH)
    cmake_parse_arguments (ARG LOCAL "" "" ${ARGN})
    if (ARG_LOCAL)
        unset (SCOPE)
        unset (OUTPUT_DIRECTORY_PROPERTIES)
    else ()
        set (SCOPE CMAKE_)
    endif ()
    foreach (TYPE ${ARG_UNPARSED_ARGUMENTS})
        set (${SCOPE}${TYPE}_OUTPUT_DIRECTORY ${OUTPUT_PATH})
        list (APPEND OUTPUT_DIRECTORY_PROPERTIES ${TYPE}_OUTPUT_DIRECTORY ${${TYPE}_OUTPUT_DIRECTORY})
        foreach (CONFIG ${CMAKE_CONFIGURATION_TYPES})
            string (TOUPPER ${CONFIG} CONFIG)
            set (${SCOPE}${TYPE}_OUTPUT_DIRECTORY_${CONFIG} ${OUTPUT_PATH})
            list (APPEND OUTPUT_DIRECTORY_PROPERTIES ${TYPE}_OUTPUT_DIRECTORY_${CONFIG} ${${TYPE}_OUTPUT_DIRECTORY_${CONFIG}})
        endforeach ()
        if (TYPE STREQUAL RUNTIME AND NOT ${OUTPUT_PATH} STREQUAL .)
            file (RELATIVE_PATH REL_OUTPUT_PATH ${CMAKE_BINARY_DIR} ${OUTPUT_PATH})
            set (DEST_RUNTIME_DIR ${REL_OUTPUT_PATH})
        endif ()
    endforeach ()
    if (ARG_LOCAL)
        list (APPEND TARGET_PROPERTIES ${OUTPUT_DIRECTORY_PROPERTIES})
    endif ()
endmacro ()

# Macro for setting up an executable target
# Macro arguments:
#  PRIVATE - setup executable target without installing it
#  TOOL - setup a tool executable target
#  NODEPS - setup executable target without defining Urho3D dependency libraries
#  WIN32/MACOSX_BUNDLE/EXCLUDE_FROM_ALL - see CMake help on add_executable() command
# CMake variables:
#  SOURCE_FILES - list of source files
#  INCLUDE_DIRS - list of directories for include search path
#  LIBS - list of dependent libraries that are built internally in the project
#  ABSOLUTE_PATH_LIBS - list of dependent libraries that are external to the project
#  LINK_DEPENDS - list of additional files on which a target binary depends for linking (Makefile-based generator only)
#  TARGET_PROPERTIES - list of target properties
macro (setup_executable)
    cmake_parse_arguments (ARG "PRIVATE;TOOL;NODEPS" "" "" ${ARGN})
    check_source_files ()
    add_executable (${TARGET_NAME} ${ARG_UNPARSED_ARGUMENTS} ${SOURCE_FILES})
    set (RUNTIME_DIR ${CMAKE_RUNTIME_OUTPUT_DIRECTORY})
    if (ARG_PRIVATE)
        set_output_directories (. LOCAL RUNTIME PDB)
        set (RUNTIME_DIR .)
    endif ()
    if (ARG_TOOL)
        list (APPEND TARGET_PROPERTIES XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH YES)
        if (NOT ARG_PRIVATE AND NOT DEST_RUNTIME_DIR MATCHES tool)
            set_output_directories (${CMAKE_BINARY_DIR}/bin/tool LOCAL RUNTIME PDB)
            set (RUNTIME_DIR ${CMAKE_BINARY_DIR}/bin/tool)
        endif ()
    endif ()
    if (NOT ARG_NODEPS)
        define_dependency_libs (Urho3D)
    endif ()
    if (XCODE AND LUAJIT_EXE_LINKER_FLAGS_APPLE)
        list (APPEND TARGET_PROPERTIES XCODE_ATTRIBUTE_OTHER_LDFLAGS[arch=x86_64] "${LUAJIT_EXE_LINKER_FLAGS_APPLE} $(OTHER_LDFLAGS)")    # Xcode universal build linker flags when targeting 64-bit OSX with LuaJIT enabled
    endif ()
    setup_target ()

    if (URHO3D_SCP_TO_TARGET)
        add_custom_command (TARGET ${TARGET_NAME} POST_BUILD COMMAND scp $<TARGET_FILE:${TARGET_NAME}> ${URHO3D_SCP_TO_TARGET} || exit 0
            COMMENT "Scp-ing ${TARGET_NAME} executable to target system")
    endif ()
    if (WIN32 AND NOT ARG_NODEPS AND URHO3D_LIB_TYPE STREQUAL SHARED AND RUNTIME_DIR)
        # Make a copy of the Urho3D DLL to the runtime directory in the build tree
        if (TARGET Urho3D)
            add_custom_command (TARGET ${TARGET_NAME} POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:Urho3D> ${RUNTIME_DIR})
        else ()
            foreach (DLL ${URHO3D_DLL})
                add_custom_command (TARGET ${TARGET_NAME} POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different ${DLL} ${RUNTIME_DIR})
            endforeach ()
        endif ()
    endif ()
    if (DIRECT3D_DLL AND NOT ARG_NODEPS AND RUNTIME_DIR)
        # Make a copy of the D3D DLL to the runtime directory in the build tree
        add_custom_command (TARGET ${TARGET_NAME} POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different ${DIRECT3D_DLL} ${RUNTIME_DIR})
    endif ()
    # Need to check if the destination variable is defined first because this macro could be called by downstream project that does not wish to install anything
    if (NOT ARG_PRIVATE)
        if (WEB AND DEST_BUNDLE_DIR)
            set (LOCATION $<TARGET_FILE_DIR:${TARGET_NAME}>)
            unset (FILES)
            foreach (EXT data html html.map html.mem js)
                list (APPEND FILES ${LOCATION}/${TARGET_NAME}.${EXT})
            endforeach ()
            install (FILES ${FILES} DESTINATION ${DEST_BUNDLE_DIR} OPTIONAL)    # We get html.map or html.mem depend on the build configuration
        elseif (DEST_RUNTIME_DIR AND (DEST_BUNDLE_DIR OR NOT IOS))
            install (TARGETS ${TARGET_NAME} RUNTIME DESTINATION ${DEST_RUNTIME_DIR} BUNDLE DESTINATION ${DEST_BUNDLE_DIR})
            if (WIN32 AND NOT ARG_NODEPS AND URHO3D_LIB_TYPE STREQUAL SHARED AND NOT URHO3D_DLL_INSTALLED)
                if (TARGET Urho3D)
                    install (FILES $<TARGET_FILE:Urho3D> DESTINATION ${DEST_RUNTIME_DIR})
                else ()
                    install (FILES ${URHO3D_DLL} DESTINATION ${DEST_RUNTIME_DIR})
                endif ()
                set (URHO3D_DLL_INSTALLED TRUE)
            endif ()
            if (DIRECT3D_DLL AND NOT DIRECT3D_DLL_INSTALLED)
                # Make a copy of the D3D DLL to the runtime directory in the installed location
                install (FILES ${DIRECT3D_DLL} DESTINATION ${DEST_RUNTIME_DIR})
                set (DIRECT3D_DLL_INSTALLED TRUE)
            endif ()
        endif ()
    endif ()
endmacro ()

# Macro for setting up a library target
# Macro arguments:
#  NODEPS - setup library target without defining Urho3D dependency libraries (applicable for downstream projects)
#  STATIC/SHARED/MODULE/EXCLUDE_FROM_ALL - see CMake help on add_library() command
# CMake variables:
#  SOURCE_FILES - list of source files
#  INCLUDE_DIRS - list of directories for include search path
#  LIBS - list of dependent libraries that are built internally in the project
#  ABSOLUTE_PATH_LIBS - list of dependent libraries that are external to the project
#  LINK_DEPENDS - list of additional files on which a target binary depends for linking (Makefile-based generator only)
#  TARGET_PROPERTIES - list of target properties
macro (setup_library)
    cmake_parse_arguments (ARG NODEPS "" "" ${ARGN})
    check_source_files ()
    add_library (${TARGET_NAME} ${ARG_UNPARSED_ARGUMENTS} ${SOURCE_FILES})
    get_target_property (LIB_TYPE ${TARGET_NAME} TYPE)
    if (NOT ARG_NODEPS AND NOT PROJECT_NAME STREQUAL Urho3D)
        define_dependency_libs (Urho3D)
    endif ()
    if (XCODE AND LUAJIT_SHARED_LINKER_FLAGS_APPLE AND LIB_TYPE STREQUAL SHARED_LIBRARY)
        list (APPEND TARGET_PROPERTIES XCODE_ATTRIBUTE_OTHER_LDFLAGS[arch=x86_64] "${LUAJIT_SHARED_LINKER_FLAGS_APPLE} $(OTHER_LDFLAGS)")    # Xcode universal build linker flags when targeting 64-bit OSX with LuaJIT enabled
    endif ()
    setup_target ()

    # Setup the compiler flags for building shared library
    if (LIB_TYPE STREQUAL SHARED_LIBRARY)
        # Hide the symbols that are not explicitly marked for export
        add_compiler_export_flags ()
    endif ()

    if (PROJECT_NAME STREQUAL Urho3D)
        # Accumulate all the dependent static libraries that are used in building the Urho3D library itself
        if (NOT ${TARGET_NAME} STREQUAL Urho3D AND LIB_TYPE STREQUAL STATIC_LIBRARY)
            set (STATIC_LIBRARY_TARGETS ${STATIC_LIBRARY_TARGETS} ${TARGET_NAME} PARENT_SCOPE)
            # When performing Xcode CI build suppress all the warnings for 3rd party libraries because there are just too many of them
            if (XCODE AND DEFINED ENV{CI})
                set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -w")
                set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -w")
            endif ()
        endif ()
    elseif (URHO3D_SCP_TO_TARGET)
        add_custom_command (TARGET ${TARGET_NAME} POST_BUILD COMMAND scp $<TARGET_FILE:${TARGET_NAME}> ${URHO3D_SCP_TO_TARGET} || exit 0
            COMMENT "Scp-ing ${TARGET_NAME} library to target system")
    endif ()
endmacro ()

# Macro for setting up an executable target with resources to copy/package/bundle/preload
# Macro arguments:
#  NODEPS - setup executable target without defining Urho3D dependency libraries
#  NOBUNDLE - do not use MACOSX_BUNDLE even when URHO3D_MACOSX_BUNDLE build option is enabled
#  WIN32/MACOSX_BUNDLE/EXCLUDE_FROM_ALL - see CMake help on add_executable() command
# CMake variables:
#  RESOURCE_DIRS - list of resource directories (will be packaged into *.pak when URHO3D_PACKAGING build option is set)
#  RESOURCE_FILES - list of additional resource files (will not be packaged into *.pak in any case)
#  SOURCE_FILES - list of source files
#  INCLUDE_DIRS - list of directories for include search path
#  LIBS - list of dependent libraries that are built internally in the project
#  ABSOLUTE_PATH_LIBS - list of dependent libraries that are external to the project
#  LINK_DEPENDS - list of additional files on which a target binary depends for linking (Makefile-based generator only)
#  TARGET_PROPERTIES - list of target properties
macro (setup_main_executable)
    cmake_parse_arguments (ARG "NOBUNDLE;MACOSX_BUNDLE;WIN32" "" "" ${ARGN})

    # Define resources
    if (NOT RESOURCE_DIRS)
        # If the macro caller has not defined the resource dirs then set them based on Urho3D project convention
        foreach (DIR ${CMAKE_SOURCE_DIR}/bin/CoreData ${CMAKE_SOURCE_DIR}/bin/Data)
            # Do not assume downstream project always follows Urho3D project convention, so double check if this directory exists before using it
            if (IS_DIRECTORY ${DIR})
                list (APPEND RESOURCE_DIRS ${DIR})
            endif ()
        endforeach ()
    endif ()
    if (URHO3D_PACKAGING AND RESOURCE_DIRS)
        # Populate all the variables required by resource packaging
        foreach (DIR ${RESOURCE_DIRS})
            get_filename_component (NAME ${DIR} NAME)
            if (ANDROID)
                set (RESOURCE_${DIR}_PATHNAME ${CMAKE_BINARY_DIR}/assets/${NAME}.pak)
            else ()
                set (RESOURCE_${DIR}_PATHNAME ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${NAME}.pak)
            endif ()
            list (APPEND RESOURCE_PAKS ${RESOURCE_${DIR}_PATHNAME})
            if (EMSCRIPTEN AND NOT EMSCRIPTEN_SHARE_DATA)
                # Set the custom EMCC_OPTION property to preload the *.pak individually
                set_source_files_properties (${RESOURCE_${DIR}_PATHNAME} PROPERTIES EMCC_OPTION preload-file EMCC_FILE_ALIAS "@/${NAME}.pak --use-preload-cache")
            endif ()
        endforeach ()
        # Urho3D project builds the PackageTool as required; downstream project uses PackageTool found in the Urho3D build tree or Urho3D SDK
        find_Urho3d_tool (PACKAGE_TOOL PackageTool
            HINTS ${CMAKE_BINARY_DIR}/bin/tool ${URHO3D_HOME}/bin/tool
            DOC "Path to PackageTool" MSG_MODE WARNING)
        if (CMAKE_PROJECT_NAME STREQUAL Urho3D)
            set (PACKAGING_DEP DEPENDS PackageTool)
        endif ()
        set (PACKAGING_COMMENT " and packaging")
        set_property (SOURCE ${RESOURCE_PAKS} PROPERTY GENERATED TRUE)
        if (WEB)
            if (EMSCRIPTEN)
                # Check if shell-file is already added in source files list by downstream project
                if (NOT CMAKE_PROJECT_NAME STREQUAL Urho3D)
                    foreach (FILE ${SOURCE_FILES})
                        get_property (EMCC_OPTION SOURCE ${FILE} PROPERTY EMCC_OPTION)
                        if (EMCC_OPTION STREQUAL shell-file)
                            set (SHELL_HTML_FOUND TRUE)
                            break ()
                        endif ()
                    endforeach ()
                endif ()
                if (NOT SHELL_HTML_FOUND)
                    # Use custom Urho3D shell.html
                    set (SHELL_HTML ${CMAKE_BINARY_DIR}/Source/shell.html)
                    list (APPEND SOURCE_FILES ${SHELL_HTML})
                    set_source_files_properties (${SHELL_HTML} PROPERTIES EMCC_OPTION shell-file)
                endif ()
                # Set the custom EMCC_OPTION property to peload the generated shared data file
                if (EMSCRIPTEN_SHARE_DATA)
                    set (SHARED_RESOURCE_JS ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${CMAKE_PROJECT_NAME}.js)
                    list (APPEND SOURCE_FILES ${SHARED_RESOURCE_JS} ${SHARED_RESOURCE_JS}.data)
                    set_source_files_properties (${SHARED_RESOURCE_JS} PROPERTIES GENERATED TRUE EMCC_OPTION pre-js)
                    # Need to check if the destination variable is defined first because this macro could be called by downstream project that does not wish to install anything
                    if (DEST_BUNDLE_DIR)
                        install (FILES ${SHARED_RESOURCE_JS} ${SHARED_RESOURCE_JS}.data DESTINATION ${DEST_BUNDLE_DIR})
                    endif ()
                endif ()
            endif ()
        endif ()
    endif ()
    if (XCODE)
        if (NOT RESOURCE_FILES)
            # Default app bundle icon
            set (RESOURCE_FILES ${CMAKE_SOURCE_DIR}/bin/Data/Textures/UrhoIcon.icns)
            if (IOS)
                # Default app icon on the iOS home screen
                list (APPEND RESOURCE_FILES ${CMAKE_SOURCE_DIR}/bin/Data/Textures/UrhoIcon.png)
            endif ()
        endif ()
        # Group them together under 'Resources' in Xcode IDE
        source_group (Resources FILES ${RESOURCE_DIRS} ${RESOURCE_PAKS} ${RESOURCE_FILES})
        # But only use either paks or dirs
        if (RESOURCE_PAKS)
            set_source_files_properties (${RESOURCE_PAKS} ${RESOURCE_FILES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
        else ()
            set_source_files_properties (${RESOURCE_DIRS} ${RESOURCE_FILES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
        endif ()
    endif ()
    list (APPEND SOURCE_FILES ${RESOURCE_DIRS} ${RESOURCE_PAKS} ${RESOURCE_FILES})

    if (ANDROID)
        # Add SDL native init function, SDL_Main() entry point must be defined by one of the source files in ${SOURCE_FILES}
        find_Urho3D_file (ANDROID_MAIN_C_PATH SDL_android_main.c
            HINTS ${URHO3D_HOME}/include/Urho3D/ThirdParty/SDL/android ${CMAKE_SOURCE_DIR}/Source/ThirdParty/SDL/src/main/android
            DOC "Path to SDL_android_main.c" MSG_MODE FATAL_ERROR)
        list (APPEND SOURCE_FILES ${ANDROID_MAIN_C_PATH})
        # Setup shared library output path
        set_output_directories (${ANDROID_LIBRARY_OUTPUT_PATH} LIBRARY)
        # Setup target as main shared library
        setup_library (SHARED)
        if (DEST_LIBRARY_DIR)
            install (TARGETS ${TARGET_NAME} LIBRARY DESTINATION ${DEST_LIBRARY_DIR} ARCHIVE DESTINATION ${DEST_LIBRARY_DIR})
        endif ()
        # Copy other dependent shared libraries to Android library output path
        foreach (FILE ${ABSOLUTE_PATH_LIBS})
            get_filename_component (EXT ${FILE} EXT)
            if (EXT STREQUAL .so)
                get_filename_component (NAME ${FILE} NAME)
                add_custom_command (TARGET ${TARGET_NAME} POST_BUILD
                    COMMAND ${CMAKE_COMMAND} ARGS -E copy_if_different ${FILE} ${ANDROID_LIBRARY_OUTPUT_PATH}
                    COMMENT "Copying ${NAME} to library output directory")
            endif ()
        endforeach ()
        if (ANDROID_NDK_GDB)
            # Copy the library while it still has debug symbols for ndk-gdb
            add_custom_command (TARGET ${TARGET_NAME} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${TARGET_NAME}> ${NDK_GDB_SOLIB_PATH}
                COMMENT "Copying lib${TARGET_NAME}.so with debug symbols to ${NDK_GDB_SOLIB_PATH} directory")
        endif ()
        # When performing packaging, include the final apk file
        if (CMAKE_PROJECT_NAME STREQUAL Urho3D AND NOT APK_INCLUDED)
            install (FILES ${LIBRARY_OUTPUT_PATH_ROOT}/bin/Urho3D-debug.apk DESTINATION ${DEST_RUNTIME_DIR} OPTIONAL)
            set (APK_INCLUDED 1)
        endif ()
    else ()
        # Setup target as executable
        if (WIN32)
            if (NOT URHO3D_WIN32_CONSOLE OR ARG_WIN32)
                set (EXE_TYPE WIN32)
            endif ()
            list (APPEND TARGET_PROPERTIES DEBUG_POSTFIX _d)
        elseif (IOS)
            set (EXE_TYPE MACOSX_BUNDLE)
            list (APPEND TARGET_PROPERTIES XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY 1,2 MACOSX_BUNDLE_INFO_PLIST iOSBundleInfo.plist.template)
        elseif (APPLE)
            if ((URHO3D_MACOSX_BUNDLE OR ARG_MACOSX_BUNDLE) AND NOT ARG_NOBUNDLE)
                set (EXE_TYPE MACOSX_BUNDLE)
                list (APPEND TARGET_PROPERTIES MACOSX_BUNDLE_INFO_PLIST MacOSXBundleInfo.plist.template)
            endif ()
        elseif (WEB)
            if (EMSCRIPTEN)
                # Pass additional source files to linker with the supported flags, such as: js-library, pre-js, post-js, embed-file, preload-file, shell-file
                foreach (FILE ${SOURCE_FILES})
                    get_property (EMCC_OPTION SOURCE ${FILE} PROPERTY EMCC_OPTION)
                    if (EMCC_OPTION)
                        list (APPEND LINK_DEPENDS ${FILE})
                        unset (EMCC_FILE_ALIAS)
                        unset (EMCC_EXCLUDE_FILE)
                        if (EMCC_OPTION STREQUAL embed-file OR EMCC_OPTION STREQUAL preload-file)
                            get_property (EMCC_FILE_ALIAS SOURCE ${FILE} PROPERTY EMCC_FILE_ALIAS)
                            get_property (EMCC_EXCLUDE_FILE SOURCE ${FILE} PROPERTY EMCC_EXCLUDE_FILE)
                            if (EMCC_EXCLUDE_FILE)
                                set (EMCC_EXCLUDE_FILE " --exclude-file ${EMCC_EXCLUDE_FILE}")
                            endif ()
                        endif ()
                        set (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} --${EMCC_OPTION} ${FILE}${EMCC_FILE_ALIAS}${EMCC_EXCLUDE_FILE}")
                    endif ()
                endforeach ()
            endif ()
        endif ()
        setup_executable (${EXE_TYPE} ${ARG_UNPARSED_ARGUMENTS})
    endif ()

    # Define a custom target for resource modification checking and resource packaging (if enabled)
    if ((EXE_TYPE STREQUAL MACOSX_BUNDLE OR URHO3D_PACKAGING) AND RESOURCE_DIRS)
        # Share a same custom target that checks for a same resource dirs list
        foreach (DIR ${RESOURCE_DIRS})
            string (MD5 MD5 ${DIR})
            set (MD5ALL ${MD5ALL}${MD5})
            if (CMAKE_HOST_WIN32)
                # On Windows host, always assumes there are changes so resource dirs would be repackaged in each build, however, still make sure the *.pak timestamp is not altered unnecessarily
                if (URHO3D_PACKAGING)
                    set (PACKAGING_COMMAND && echo Packaging ${DIR}... && ${PACKAGE_TOOL} ${DIR} ${RESOURCE_${DIR}_PATHNAME}.new -c -q && ${CMAKE_COMMAND} -E copy_if_different ${RESOURCE_${DIR}_PATHNAME}.new ${RESOURCE_${DIR}_PATHNAME} && ${CMAKE_COMMAND} -E remove ${RESOURCE_${DIR}_PATHNAME}.new)
                endif ()
                list (APPEND COMMANDS COMMAND ${CMAKE_COMMAND} -E touch ${DIR} ${PACKAGING_COMMAND})
            else ()
                # On Unix-like hosts, detect the changes in the resource directory recursively so they are only repackaged and/or rebundled (Xcode only) as necessary
                if (URHO3D_PACKAGING)
                    set (PACKAGING_COMMAND && echo Packaging ${DIR}... && ${PACKAGE_TOOL} ${DIR} ${RESOURCE_${DIR}_PATHNAME} -c -q)
                    set (OUTPUT_COMMAND test -e ${RESOURCE_${DIR}_PATHNAME} || \( true ${PACKAGING_COMMAND} \))
                else ()
                    set (OUTPUT_COMMAND true)   # Nothing to output
                endif ()
                list (APPEND COMMANDS COMMAND echo Checking ${DIR}... && bash -c \"\(\( `find ${DIR} -newer ${DIR} |wc -l` \)\)\" && touch -cm ${DIR} ${PACKAGING_COMMAND} || ${OUTPUT_COMMAND})
            endif ()
        endforeach ()
        string (MD5 MD5ALL ${MD5ALL})
        # Ensure the resource check is done before building the main executable target
        if (NOT RESOURCE_CHECK_${MD5ALL})
            set (RESOURCE_CHECK RESOURCE_CHECK)
            while (TARGET ${RESOURCE_CHECK})
                string (RANDOM RANDOM)
                set (RESOURCE_CHECK RESOURCE_CHECK_${RANDOM})
            endwhile ()
            set (RESOURCE_CHECK_${MD5ALL} ${RESOURCE_CHECK} CACHE INTERNAL "Resource check hash map")
        endif ()
        if (NOT TARGET ${RESOURCE_CHECK_${MD5ALL}})
            add_custom_target (${RESOURCE_CHECK_${MD5ALL}} ALL ${COMMANDS} ${PACKAGING_DEP} COMMENT "Checking${PACKAGING_COMMENT} resource directories")
        endif ()
        add_dependencies (${TARGET_NAME} ${RESOURCE_CHECK_${MD5ALL}})
    endif ()

    # Define a custom command for generating a shared data file (if enabled)
    if (EMSCRIPTEN_SHARE_DATA AND RESOURCE_PAKS)
        # When sharing a single data file, all main targets are assumed to use a same set of resource paks
        foreach (FILE ${RESOURCE_PAKS})
            get_filename_component (NAME ${FILE} NAME)
            list (APPEND PAK_NAMES ${NAME})
        endforeach ()
        if (CMAKE_BUILD_TYPE STREQUAL Debug AND EMSCRIPTEN_EMCC_VERSION VERSION_GREATER 1.32.2)
            set (SEPARATE_METADATA --separate-metadata)
        endif ()
        add_custom_command (OUTPUT ${SHARED_RESOURCE_JS}.data
            COMMAND ${EMPACKAGER} ${SHARED_RESOURCE_JS}.data --preload ${PAK_NAMES} --js-output=${SHARED_RESOURCE_JS} --use-preload-cache ${SEPARATE_METADATA}
            DEPENDS RESOURCE_CHECK ${RESOURCE_PAKS}
            WORKING_DIRECTORY ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
            COMMENT "Generating shared data file")
    endif ()

    # Define a custom command for stripping the main target executable (or shared library for Android) for Release build configuration
    if (CMAKE_BUILD_TYPE STREQUAL Release AND NOT WEB)  # This condition excludes Xcode and VS as they are multi-config, which is exactly what we want too
        add_custom_command (TARGET ${TARGET_NAME} POST_BUILD COMMAND ${CMAKE_STRIP} $<TARGET_FILE:${TARGET_NAME}>)
    endif ()
endmacro ()

# Macro for setting up dependency lib for compilation and linking of a target
macro (setup_target)
    # Include directories
    include_directories (${INCLUDE_DIRS})
    # Link libraries
    define_dependency_libs (${TARGET_NAME})
    target_link_libraries (${TARGET_NAME} ${ABSOLUTE_PATH_LIBS} ${LIBS})
    # Enable PCH if requested
    if (${TARGET_NAME}_HEADER_PATHNAME)
        enable_pch (${${TARGET_NAME}_HEADER_PATHNAME})
    endif ()
    # Set additional linker dependencies (only work for Makefile-based generator according to CMake documentation)
    if (LINK_DEPENDS)
        string (REPLACE ";" "\;" LINK_DEPENDS "${LINK_DEPENDS}")        # Stringify for string replacement
        list (APPEND TARGET_PROPERTIES LINK_DEPENDS "${LINK_DEPENDS}")  # Stringify with semicolons already escaped
        unset (LINK_DEPENDS)
    endif ()
    # Extra compiler flags for Xcode which are dynamically changed based on active arch in order to support Mach-O universal binary targets
    # We don't add the ABI flag for Xcode because it automatically passes '-arch i386' compiler flag when targeting 32 bit which does the same thing as '-m32'
    if (XCODE)
        # Speed up build when in Debug configuration by building active arch only
        list (FIND TARGET_PROPERTIES XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH ATTRIBUTE_ALREADY_SET)
        if (ATTRIBUTE_ALREADY_SET EQUAL -1)
            list (APPEND TARGET_PROPERTIES XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH $<$<CONFIG:Debug>:YES>)
        endif ()
        if (NOT URHO3D_SSE)
            # Nullify the Clang default so that it is consistent with GCC
            list (APPEND TARGET_PROPERTIES XCODE_ATTRIBUTE_OTHER_CFLAGS[arch=i386] "-mno-sse $(OTHER_CFLAGS)")
            list (APPEND TARGET_PROPERTIES XCODE_ATTRIBUTE_OTHER_CPLUSPLUSFLAGS[arch=i386] "-mno-sse $(OTHER_CPLUSPLUSFLAGS)")
        endif ()
    endif ()
    if (TARGET_PROPERTIES)
        set_target_properties (${TARGET_NAME} PROPERTIES ${TARGET_PROPERTIES})
        unset (TARGET_PROPERTIES)
    endif ()

    # Workaround CMake/Xcode generator bug where it always appends '/build' path element to SYMROOT attribute and as such the items in Products are always rendered as red in the Xcode IDE as if they are not yet built
    if (NOT DEFINED ENV{TRAVIS})
        if (XCODE AND NOT CMAKE_PROJECT_NAME MATCHES ^Urho3D-ExternalProject-)
            file (MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/build)
            get_target_property (LOCATION ${TARGET_NAME} LOCATION)
            string (REGEX REPLACE "^.*\\$\\(CONFIGURATION\\)" $(CONFIGURATION) SYMLINK ${LOCATION})
            get_filename_component (DIRECTORY ${SYMLINK} PATH)
            add_custom_command (TARGET ${TARGET_NAME} POST_BUILD
                COMMAND mkdir -p ${DIRECTORY} && ln -sf $<TARGET_FILE:${TARGET_NAME}> ${DIRECTORY}/$<TARGET_FILE_NAME:${TARGET_NAME}>
                WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/build)
        endif ()
    endif ()
endmacro ()

# Macro for setting up a test case
macro (setup_test)
    if (URHO3D_TESTING)
        cmake_parse_arguments (ARG "" NAME OPTIONS ${ARGN})
        if (NOT ARG_NAME)
            set (ARG_NAME ${TARGET_NAME})
        endif ()
        list (APPEND ARG_OPTIONS -timeout ${URHO3D_TEST_TIMEOUT})
        if (WEB)
            if (EMSCRIPTEN)
                if (DEFINED ENV{CI})
                    # The latency on CI server could be very high at time, so add some adjustment
                    # If it is not enough causing a test case failure then so be it because it is better that than wait for it and still ends up in build error due to time limit
                    set (EMRUN_TIMEOUT_ADJUSTMENT + 8 * \\${URHO3D_TEST_TIMEOUT})
                    set (EMRUN_TIMEOUT_RETURNCODE --timeout_returncode 0)
                endif ()
                math (EXPR EMRUN_TIMEOUT "2 * ${URHO3D_TEST_TIMEOUT} ${EMRUN_TIMEOUT_ADJUSTMENT}")
                add_test (NAME ${ARG_NAME} COMMAND ${EMRUN} --browser ${EMSCRIPTEN_EMRUN_BROWSER} --timeout ${EMRUN_TIMEOUT} ${EMRUN_TIMEOUT_RETURNCODE} --kill_exit ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${TARGET_NAME}.html ${ARG_OPTIONS})
            endif ()
        else ()
            add_test (NAME ${ARG_NAME} COMMAND ${TARGET_NAME} ${ARG_OPTIONS})
        endif ()
    endif ()
endmacro ()
