using Test

function f(x, y=0)
    leaf_function(x, y, 1)
    leaf_function(x, y, 2)
    leaf_function(x, y, 3)
    leaf_function(x, y, 4)
    leaf_function(x, y, 5)
    leaf_function(x, y, 6)
end
function g()
    f(11, 12)
    leaf_function(100)
    f(12, 15)
end
h() = g()
function k()
    leaf_function(100)
end
function top_function()
    h()
    k()
end


import InteractiveUtils: @code_typed
import Core.Compiler: IRCode
import Poptart: groupwise_codestack
import AbstractTrees: print_tree
using Millboard # table
using DataLogger # read_stdout

(src,) = @code_typed top_function()
code = Core.Compiler.inflate_ir(src, Core.svec())::IRCode
codestack = groupwise_codestack(code)

Millboard.display_style[:prepend_newline] = true
DataLogger.read_stdout() do
    println(table(codestack.A))
end == """

|    | 1 |  2 | 3 |  4 |
|----|---|----|---|----|
|  1 | 1 |  3 | 4 |  7 |
|  2 | 1 |  3 | 4 |  8 |
|  3 | 1 |  3 | 4 |  9 |
|  4 | 1 |  3 | 4 | 10 |
|  5 | 1 |  3 | 4 | 11 |
|  6 | 1 |  3 | 4 | 12 |
|  7 | 1 |  3 | 5 |    |
|  8 | 1 |  3 | 6 | 13 |
|  9 | 1 |  3 | 6 | 14 |
| 10 | 1 |  3 | 6 | 15 |
| 11 | 1 |  3 | 6 | 16 |
| 12 | 1 |  3 | 6 | 17 |
| 13 | 1 |  3 | 6 | 18 |
| 14 | 2 | 19 |   |    |
| 15 | 2 |    |   |    |
"""

@test DataLogger.read_stdout() do
    print_tree(codestack.tree)
end ==  """
(value = nothing, range = 1:15)
├─ (value = 1, range = 1:13)
│  └─ (value = 3, range = 1:13)
│     ├─ (value = 4, range = 1:6)
│     │  ├─ (value = 7, range = 1:1)
│     │  ├─ (value = 8, range = 2:2)
│     │  ├─ (value = 9, range = 3:3)
│     │  ├─ (value = 10, range = 4:4)
│     │  ├─ (value = 11, range = 5:5)
│     │  └─ (value = 12, range = 6:6)
│     ├─ (value = 5, range = 7:7)
│     └─ (value = 6, range = 8:13)
│        ├─ (value = 13, range = 8:8)
│        ├─ (value = 14, range = 9:9)
│        ├─ (value = 15, range = 10:10)
│        ├─ (value = 16, range = 11:11)
│        ├─ (value = 17, range = 12:12)
│        └─ (value = 18, range = 13:13)
└─ (value = 2, range = 14:15)
   └─ (value = 19, range = 14:14)
"""

(src,) = @code_typed length("abc")
code = Core.Compiler.inflate_ir(src, Core.svec())::IRCode
codestack = groupwise_codestack(code)
@test (212,11) == size(codestack.A)
