# CMake常用指令手册（附文件夹结构示例）

本文档整理CMake开发中最常用、最实用的指令，按“基础配置→目标构建→路径/依赖→高级配置”分类，每个指令包含「作用说明\+语法格式\+用法示例」，并搭配不同场景的项目文件夹结构，适配单文件、多文件、带库文件的常见项目，新手可直接对照使用。

# 一、基础配置指令（必用，项目开篇必备）

此类指令用于设置CMake基础环境、项目信息，是CMakeLists\.txt的开篇核心，所有项目都需包含。

## 1\. cmake\_minimum\_required

**作用**：指定当前项目所需的最低CMake版本，避免因版本兼容问题导致构建失败。

**语法**：cmake\_minimum\_required\(VERSION \&lt;版本号\&gt; \[FATAL\_ERROR\]\)

**说明**：VERSION后接具体版本（如3\.10、3\.16），可选FATAL\_ERROR表示版本不满足时直接报错终止构建。

**示例**：

```cmake
# 指定最低CMake版本为3.10，版本不够则报错
cmake_minimum_required(VERSION 3.10 FATAL_ERROR)
```

## 2\. project

**作用**：定义项目名称、版本、编程语言，可选指定项目描述、主页等信息，是CMake识别项目的核心指令。

**语法**：project\(\&lt;项目名\&gt; \[VERSION \&lt;版本\&gt;\] \[LANGUAGES \&lt;语言\&gt;\] \[DESCRIPTION \&lt;描述\&gt;\] \[HOMEPAGE\_URL \&lt;链接\&gt;\]\)

**说明**：LANGUAGES可选C、CXX（C\+\+）、Fortran等，默认自动检测；VERSION格式为“主\.次\.修订\.补丁”（如1\.0\.0）。

**示例**：

```cmake
# 定义项目名称为MyProject，版本1.0.0，支持C++
project(MyProject VERSION 1.0.0 LANGUAGES CXX DESCRIPTION "A simple C++ project")
```

## 3\. set

**作用**：设置变量（全局变量、局部变量、缓存变量），用于存储路径、编译选项、源文件列表等，是CMake中最灵活的指令之一。

**语法**：set\(\&lt;变量名\&gt; \&lt;值1\&gt; \[\&lt;值2\&gt; \.\.\.\] \[CACHE \&lt;类型\&gt; \&lt;描述 \&gt; \[FORCE\]\]\)

**说明**：不写CACHE则为普通变量，写CACHE则为缓存变量（可在cmake\-gui中修改）；常用变量如CMAKE\_CXX\_STANDARD（C\+\+版本）。

**示例**：

```cmake
# 设置C++版本为11，强制生效
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置源文件列表变量
set(SRC_FILES main.cpp func.cpp)
```

# 二、目标构建指令（核心，生成可执行文件/库文件）

此类指令用于定义构建目标（可执行文件、静态库、动态库），指定目标依赖的源文件，是实现项目编译的核心。

## 1\. add\_executable

**作用**：生成可执行文件，指定目标名称和依赖的源文件。

**语法**：add\_executable\(\&lt;目标名\&gt; \[WIN32\] \[MACOSX\_BUNDLE\] \&lt;源文件1\&gt; \[\&lt;源文件2\&gt; \.\.\.\]\)

**说明**：WIN32（Windows）、MACOSX\_BUNDLE（macOS）为可选，用于生成对应平台的可执行文件格式；源文件可直接写文件名，也可引用变量。

**示例**：

```cmake
# 生成可执行文件main，依赖main.cpp和func.cpp
add_executable(main main.cpp func.cpp)

# 引用变量SRC_FILES生成可执行文件
add_executable(app ${SRC_FILES})
```

## 2\. add\_library

**作用**：生成库文件（静态库、动态库、模块库），指定库名称、库类型和依赖的源文件。

**语法**：add\_library\(\&lt;库名\&gt; \[STATIC \| SHARED \| MODULE\] \[EXCLUDE\_FROM\_ALL\] \&lt;源文件1\&gt; \[\&lt;源文件2\&gt; \.\.\.\]\)

**说明**：

- STATIC：静态库（\.a/\.lib），编译时直接链接到目标文件
- SHARED：动态库（\.so/\.dll），运行时加载
- MODULE：模块库（仅在部分平台生效，如Linux）
- EXCLUDE\_FROM\_ALL：该库不会被默认构建，需手动指定构建

**示例**：

```cmake
# 生成静态库libmymath.a（Linux）/mymath.lib（Windows）
add_library(mymath STATIC math.cpp)

# 生成动态库libmyutils.so（Linux）/myutils.dll（Windows）
add_library(myutils SHARED utils.cpp)
```

## 3\. target\_link\_libraries

**作用**：为目标（可执行文件/库文件）链接依赖的库文件（自己生成的库、系统库、第三方库）。

**语法**：target\_link\_libraries\(\&lt;目标名\&gt; \[PRIVATE \| PUBLIC \| INTERFACE\] \&lt;库名1\&gt; \[\&lt;库名2\&gt; \.\.\.\]\)

**说明**：

- PRIVATE：仅当前目标依赖该库，依赖不会传递
- PUBLIC：当前目标依赖该库，且依赖会传递给引用当前目标的其他目标
- INTERFACE：当前目标不依赖该库，但引用当前目标的其他目标会依赖该库

**示例**：

```cmake
# 为可执行文件main链接静态库mymath和系统库pthread（Linux线程库）
target_link_libraries(main PRIVATE mymath pthread)

# 为动态库myutils链接第三方库opencv
target_link_libraries(myutils PUBLIC opencv_core opencv_imgproc)
```

# 三、路径与依赖配置指令（常用，解决头文件、库文件路径问题）

此类指令用于指定头文件路径、库文件路径，查找系统/第三方依赖，解决“找不到头文件”“找不到库文件”的常见问题。

## 1\. include\_directories

**作用**：添加头文件搜索路径，让编译器能找到\#include引用的头文件（全局生效）。

**语法**：include\_directories\(\[AFTER \| BEFORE\] \[SYSTEM\] \&lt;路径1\&gt; \[\&lt;路径2\&gt; \.\.\.\]\)

**说明**：AFTER（默认）表示在系统路径后添加，BEFORE表示在系统路径前添加；SYSTEM表示将路径视为系统头文件路径，屏蔽部分警告。

**示例**：

```cmake
# 添加当前目录下的include文件夹和../third_party/include路径
include_directories(include ../third_party/include)
```

## 2\. target\_include\_directories

**作用**：为指定目标添加头文件搜索路径（目标级生效，比include\_directories更灵活，推荐使用）。

**语法**：target\_include\_directories\(\&lt;目标名\&gt; \[PRIVATE \| PUBLIC \| INTERFACE\] \&lt;路径1\&gt; \[\&lt;路径2\&gt; \.\.\.\]\)

**说明**：作用范围仅针对指定目标，依赖传递规则同target\_link\_libraries。

**示例**：

```cmake
# 为可执行文件main添加头文件路径，仅main生效
target_include_directories(main PRIVATE include)
```

## 3\. link\_directories

**作用**：添加库文件搜索路径，让链接器能找到需要链接的库文件（全局生效）。

**语法**：link\_directories\(\&lt;路径1\&gt; \[\&lt;路径2\&gt; \.\.\.\]\)

**示例**：

```cmake
# 添加当前目录下的lib文件夹和../third_party/lib路径
link_directories(lib ../third_party/lib)
```

## 4\. target\_link\_directories

**作用**：为指定目标添加库文件搜索路径（目标级生效，推荐使用）。

**语法**：target\_link\_directories\(\&lt;目标名\&gt; \[PRIVATE \| PUBLIC \| INTERFACE\] \&lt;路径1\&gt; \[\&lt;路径2\&gt; \.\.\.\]\)

**示例**：

```cmake
# 为库文件mymath添加库搜索路径，仅mymath生效
target_link_directories(mymath PRIVATE lib)
```

## 5\. find\_package

**作用**：查找系统或第三方库的配置文件，自动获取库的头文件路径、库文件路径，无需手动指定（常用於第三方库，如OpenCV、Qt）。

**语法**：find\_package\(\&lt;库名\&gt; \[VERSION \&lt;版本\&gt;\] \[REQUIRED\] \[COMPONENTS \&lt;组件1\&gt; \&lt;组件2\&gt; \.\.\.\]\)

**说明**：

- REQUIRED：表示该库是必须的，找不到则报错终止构建
- COMPONENTS：指定需要的库组件（如Qt的Core、Gui组件）

**示例**：

```cmake
# 查找OpenCV库，版本至少4.0，必须找到，需core、imgproc组件
find_package(OpenCV 4.0 REQUIRED COMPONENTS core imgproc)

# 查找Qt5的Core、Gui、Widgets组件
find_package(Qt5 REQUIRED COMPONENTS Core Gui Widgets)
```

# 四、辅助指令（提升开发效率，简化配置）

此类指令用于简化配置、批量处理文件、设置编译选项等，提升CMakeLists\.txt的可读性和维护性。

## 1\. aux\_source\_directory

**作用**：自动收集指定目录下的所有源文件（\.c/\.cpp等），存储到变量中，避免手动罗列所有源文件。

**语法**：aux\_source\_directory\(\&lt;目录路径\&gt; \&lt;变量名\&gt;\)

**说明**：仅收集指定目录下的一级源文件，不递归收集子目录文件。

**示例**：

```cmake
# 收集当前目录下所有.cpp文件，存储到SRC_FILES变量
aux_source_directory(. SRC_FILES)

# 收集src目录下所有.cpp文件，存储到SRC_SRC变量
aux_source_directory(src SRC_SRC)
```

## 2\. file

**作用**：文件操作，可用于递归收集源文件、复制文件、创建目录等，功能比aux\_source\_directory更强大。

**常用语法**：

- 递归收集源文件：file\(GLOB\_RECURSE \&lt;变量名\&gt; \&lt;路径/匹配规则\&gt;\)
- 复制文件：file\(COPY \&lt;源路径\&gt; DESTINATION \&lt;目标路径\&gt;\)

**示例**：

```cmake
# 递归收集src目录下所有.cpp和.h文件
file(GLOB_RECURSE ALL_SRC "src/*.cpp" "src/*.h")

# 将resource目录下的所有文件复制到构建目录的resource文件夹
file(COPY ${CMAKE_SOURCE_DIR}/resource DESTINATION ${CMAKE_BINARY_DIR})
```

## 3\. target\_compile\_options

**作用**：为指定目标设置编译选项（如警告等级、优化等级），目标级生效。

**语法**：target\_compile\_options\(\&lt;目标名\&gt; \[PRIVATE \| PUBLIC \| INTERFACE\] \&lt;选项1\&gt; \[\&lt;选项2\&gt; \.\.\.\]\)

**示例**：

```cmake
# 为main目标设置警告等级（Linux）、优化等级O2
target_compile_options(main PRIVATE -Wall -Wextra -O2)

# 为Windows平台添加宏定义
if(WIN32)
    target_compile_options(main PRIVATE -D_WIN32)
endif()
```

## 4\. add\_subdirectory

**作用**：添加子目录，CMake会自动查找子目录下的CMakeLists\.txt并执行，用于多模块项目（如主程序\+子库）。

**语法**：add\_subdirectory\(\&lt;子目录路径\&gt; \[\&lt;构建目录\&gt;\]\)

**说明**：可选构建目录用于指定子模块的构建输出路径，默认与子目录同名。

**示例**：

```cmake
# 添加子目录lib（包含mymath库的CMakeLists.txt）
add_subdirectory(lib)
```

# 五、常见项目文件夹结构示例（搭配CMake指令使用）

以下是3种最常用的项目结构，每个结构对应完整的CMakeLists\.txt示例，可直接复制修改使用。

## 示例1：单文件项目（简单可执行文件）

### 文件夹结构

```bash
MySingleProject/          # 项目根目录
├── CMakeLists.txt        # 主CMake配置文件
└── main.cpp              # 唯一源文件
```

### CMakeLists\.txt示例

```cmake
# 最低CMake版本
cmake_minimum_required(VERSION 3.10 FATAL_ERROR)

# 项目信息
project(MySingleProject VERSION 1.0.0 LANGUAGES CXX)

# 设置C++版本
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 生成可执行文件
add_executable(main main.cpp)
```

## 示例2：多文件项目（无库，仅可执行文件）

### 文件夹结构

```bash
MyMultiFileProject/       # 项目根目录
├── CMakeLists.txt        # 主CMake配置文件
├── include/              # 头文件目录
│   ├── func.h
│   └── math.h
└── src/                  # 源文件目录
    ├── main.cpp
    ├── func.cpp
    └── math.cpp
```

### CMakeLists\.txt示例

```cmake
cmake_minimum_required(VERSION 3.10 FATAL_ERROR)
project(MyMultiFileProject VERSION 1.0.0 LANGUAGES CXX)

# 设置C++版本
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 递归收集src目录下所有.cpp文件
file(GLOB_RECURSE SRC_FILES "src/*.cpp")

# 添加头文件路径
target_include_directories(main PRIVATE include)

# 生成可执行文件
add_executable(main ${SRC_FILES})
```

## 示例3：多模块项目（主程序\+自定义库）

### 文件夹结构

```bash
MyModuleProject/          # 项目根目录
├── CMakeLists.txt        # 主CMake配置文件
├── app/                  # 主程序目录
│   ├── CMakeLists.txt    # 主程序CMake配置
│   └── main.cpp
└── lib/                  # 自定义库目录
    ├── CMakeLists.txt    # 库的CMake配置
    ├── include/          # 库的头文件
    │   └── mymath.h
    └── src/              # 库的源文件
        └── mymath.cpp
```

### CMakeLists\.txt示例（根目录）

```cmake
cmake_minimum_required(VERSION 3.10 FATAL_ERROR)
project(MyModuleProject VERSION 1.0.0 LANGUAGES CXX)

# 添加子目录（先添加库，再添加主程序，确保主程序能找到库）
add_subdirectory(lib)
add_subdirectory(app)
```

### CMakeLists\.txt示例（lib目录）

```cmake
cmake_minimum_required(VERSION 3.10)

# 收集库的源文件
file(GLOB_RECURSE LIB_SRC "src/*.cpp")

# 生成静态库
add_library(mymath STATIC ${LIB_SRC})

# 为库添加头文件路径
target_include_directories(mymath PUBLIC include)

# 设置C++版本
set_target_properties(mymath PROPERTIES CXX_STANDARD 11 CXX_STANDARD_REQUIRED ON)
```

### CMakeLists\.txt示例（app目录）

```cmake
cmake_minimum_required(VERSION 3.10)

# 生成主程序可执行文件
add_executable(app main.cpp)

# 链接自定义库mymath
target_link_libraries(app PRIVATE mymath)

# 设置C++版本
set_target_properties(app PROPERTIES CXX_STANDARD 11 CXX_STANDARD_REQUIRED ON)
```

# 六、补充说明

- CMake构建流程：创建build目录（外部构建，推荐）→ cd build → cmake \.\. → make → 生成可执行文件/库文件。
- 变量说明：CMAKE\_SOURCE\_DIR（项目根目录）、CMAKE\_BINARY\_DIR（构建目录），可在CMakeLists\.txt中直接使用。
- 跨平台适配：可通过if\(WIN32\)、if\(UNIX\)等条件判断，设置不同平台的编译选项、路径。

> （注：文档部分内容可能由 AI 生成）
