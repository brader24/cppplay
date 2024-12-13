include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(cppplay_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(cppplay_setup_options)
  option(cppplay_ENABLE_HARDENING "Enable hardening" ON)
  option(cppplay_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    cppplay_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    cppplay_ENABLE_HARDENING
    OFF)

  cppplay_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR cppplay_PACKAGING_MAINTAINER_MODE)
    option(cppplay_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(cppplay_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(cppplay_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(cppplay_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(cppplay_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(cppplay_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(cppplay_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(cppplay_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(cppplay_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(cppplay_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(cppplay_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(cppplay_ENABLE_PCH "Enable precompiled headers" OFF)
    option(cppplay_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(cppplay_ENABLE_IPO "Enable IPO/LTO" ON)
    option(cppplay_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(cppplay_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(cppplay_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(cppplay_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(cppplay_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(cppplay_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(cppplay_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(cppplay_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(cppplay_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(cppplay_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(cppplay_ENABLE_PCH "Enable precompiled headers" OFF)
    option(cppplay_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      cppplay_ENABLE_IPO
      cppplay_WARNINGS_AS_ERRORS
      cppplay_ENABLE_USER_LINKER
      cppplay_ENABLE_SANITIZER_ADDRESS
      cppplay_ENABLE_SANITIZER_LEAK
      cppplay_ENABLE_SANITIZER_UNDEFINED
      cppplay_ENABLE_SANITIZER_THREAD
      cppplay_ENABLE_SANITIZER_MEMORY
      cppplay_ENABLE_UNITY_BUILD
      cppplay_ENABLE_CLANG_TIDY
      cppplay_ENABLE_CPPCHECK
      cppplay_ENABLE_COVERAGE
      cppplay_ENABLE_PCH
      cppplay_ENABLE_CACHE)
  endif()

  cppplay_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (cppplay_ENABLE_SANITIZER_ADDRESS OR cppplay_ENABLE_SANITIZER_THREAD OR cppplay_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(cppplay_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(cppplay_global_options)
  if(cppplay_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    cppplay_enable_ipo()
  endif()

  cppplay_supports_sanitizers()

  if(cppplay_ENABLE_HARDENING AND cppplay_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR cppplay_ENABLE_SANITIZER_UNDEFINED
       OR cppplay_ENABLE_SANITIZER_ADDRESS
       OR cppplay_ENABLE_SANITIZER_THREAD
       OR cppplay_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${cppplay_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${cppplay_ENABLE_SANITIZER_UNDEFINED}")
    cppplay_enable_hardening(cppplay_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(cppplay_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(cppplay_warnings INTERFACE)
  add_library(cppplay_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  cppplay_set_project_warnings(
    cppplay_warnings
    ${cppplay_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(cppplay_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    cppplay_configure_linker(cppplay_options)
  endif()

  include(cmake/Sanitizers.cmake)
  cppplay_enable_sanitizers(
    cppplay_options
    ${cppplay_ENABLE_SANITIZER_ADDRESS}
    ${cppplay_ENABLE_SANITIZER_LEAK}
    ${cppplay_ENABLE_SANITIZER_UNDEFINED}
    ${cppplay_ENABLE_SANITIZER_THREAD}
    ${cppplay_ENABLE_SANITIZER_MEMORY})

  set_target_properties(cppplay_options PROPERTIES UNITY_BUILD ${cppplay_ENABLE_UNITY_BUILD})

  if(cppplay_ENABLE_PCH)
    target_precompile_headers(
      cppplay_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(cppplay_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    cppplay_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(cppplay_ENABLE_CLANG_TIDY)
    cppplay_enable_clang_tidy(cppplay_options ${cppplay_WARNINGS_AS_ERRORS})
  endif()

  if(cppplay_ENABLE_CPPCHECK)
    cppplay_enable_cppcheck(${cppplay_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(cppplay_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    cppplay_enable_coverage(cppplay_options)
  endif()

  if(cppplay_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(cppplay_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(cppplay_ENABLE_HARDENING AND NOT cppplay_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR cppplay_ENABLE_SANITIZER_UNDEFINED
       OR cppplay_ENABLE_SANITIZER_ADDRESS
       OR cppplay_ENABLE_SANITIZER_THREAD
       OR cppplay_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    cppplay_enable_hardening(cppplay_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
