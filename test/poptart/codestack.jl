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
import Poptart
import AbstractTrees: print_tree, printnode
using Millboard # table
using DataLogger # read_stdout

(src,) = @code_typed top_function()
code = Core.Compiler.inflate_ir(src)::IRCode
codestack = Poptart.groupwise_codestack(code)

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


function printnode(io::IO, node::Poptart.Node{<:NamedTuple})
    entry = node.data.value
    if entry === nothing
        Base.printstyled(io, (method=nothing, range=node.data.range), color=:blue)
    else
        Base.printstyled(io, (method=entry.method, range=node.data.range), color=:blue)
    end
end

@test DataLogger.read_stdout() do
    print_tree(codestack.tree)
end ==  """
(method = nothing, range = 1:15)
├─ (method = :top_function, range = 1:13)
│  └─ (method = :h, range = 1:13)
│     ├─ (method = :g, range = 1:6)
│     │  ├─ (method = :f, range = 1:1)
│     │  ├─ (method = :f, range = 2:2)
│     │  ├─ (method = :f, range = 3:3)
│     │  ├─ (method = :f, range = 4:4)
│     │  ├─ (method = :f, range = 5:5)
│     │  └─ (method = :f, range = 6:6)
│     ├─ (method = :g, range = 7:7)
│     └─ (method = :g, range = 8:13)
│        ├─ (method = :f, range = 8:8)
│        ├─ (method = :f, range = 9:9)
│        ├─ (method = :f, range = 10:10)
│        ├─ (method = :f, range = 11:11)
│        ├─ (method = :f, range = 12:12)
│        └─ (method = :f, range = 13:13)
└─ (method = :top_function, range = 14:15)
   └─ (method = :k, range = 14:14)
"""

(src,) = @code_typed length("abc")
code = Core.Compiler.inflate_ir(src)::IRCode
codestack = Poptart.groupwise_codestack(code)
@test (217,11) == size(codestack.A)
