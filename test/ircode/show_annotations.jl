import Core: CodeInfo, PhiNode, PhiCNode, PiNode, UpsilonNode, SSAValue
import Core.Compiler: Params, CodeInfo, InferenceState, InferenceResult, IRCode, ReturnNode, GotoIfNot, Argument
import Core.Compiler: scan_ssa_use!, isexpr
import Base: IdSet, sourceinfo_slotnames
import Base.IRShow: compute_inlining_depth, compute_loc_stack, should_print_ssa_type, default_expr_type_printer
import Base.IRShow: print_node


# code from julia/base/compiler/ssair/show.jl  compute_ir_line_annotations
"""
    Compute line number annotations for an IRCode

This functions compute three sets of annotations for each IR line. Take the following
example (taken from `@code_typed sin(1.0)`):

```
    **                                                    ***         **********
    35 6 ── %10  = :(Base.mul_float)(%%2, %%2)::Float64   │╻╷         sin_kernel
       │    %11  = :(Base.mul_float)(%10, %10)::Float64   ││╻          *
```

The three annotations are indicated with `*`. The first one is the line number of the
active function (printed once whenver the outer most line number changes). The second
is the inlining indicator. The number of lines indicate the level of nesting, with a
half-size line (╷) indicating the start of a scope and a full size line (│) indicating
a continuing scope. The last annotation is the most complicated one. It is a heuristic
way to print the name of the entered scope. What it attempts to do is print the outermost
scope that hasn't been printed before. Let's work a number of examples to see the impacts
and tradeoffs involved.

```
f() = leaf_function() # Delibarately not defined to end up in the IR verbatim
g() = f()
h() = g()
top_function() = h()
```

After inlining, we end up with:
```
1 1 ─ %1 = :(Main.leaf_function)()::Any   │╻╷╷ h
  └──      return %1                      │
```

We see that the only function printed is the outermost function. This certainly loses
some information, but the idea is that the outermost function would have the most
semantic meaning (in the context of the function we're looking at).

On the other hand, let's see what happens when we redefine f:
```
function f()
    leaf_function()
    leaf_function()
    leaf_function()
end
```

We get:
```
1 1 ─      :(Main.leaf_function)()::Any   │╻╷╷ h
  │        :(Main.leaf_function)()::Any   ││┃│  g
  │   %3 = :(Main.leaf_function)()::Any   │││┃   f
  └──      return %3                      │
```

Even though we were in the `f` scope since the first statement, it tooks us two statements
to catch up and print the intermediate scopes. Which scope is printed is indicated both
by the indentation of the method name and by an increased thickness of the appropriate
line for the scope.
"""
function compute_ir_line_annotations2(code::IRCode)
    loc_annotations = String[]
    loc_methods = String[]
    loc_lineno = String[]
    cur_group = 1
    last_line = 0
    last_lineno = 0
    last_stack = []
    last_printed_depth = 0
    for idx in eachindex(code.stmts)
        buf = IOBuffer()
        line = code.lines[idx]
        depth = compute_inlining_depth(code.linetable, line)
        iline = line
        lineno = 0
        loc_method = ""
        print(buf, "│")
        if line !== 0
            stack = compute_loc_stack(code, line)
            lineno = code.linetable[stack[1]].line
            x = min(length(last_stack), length(stack))
            if length(stack) != 0
                # Compute the last depth that was in common
                first_mismatch = findfirst(i->last_stack[i] != stack[i], 1:x)
                # If the first mismatch is the last stack frame, that might just
                # be a line number mismatch in inner most frame. Ignore those
                if length(last_stack) == length(stack) && first_mismatch == length(stack)
                    last_entry, entry = code.linetable[last_stack[end]], code.linetable[stack[end]]
                    if last_entry.method == entry.method && last_entry.file == entry.file
                        first_mismatch = nothing
                    end
                end
                last_depth = something(first_mismatch, x+1)-1
                if min(depth, last_depth) > last_printed_depth
                    printing_depth = min(depth, last_printed_depth + 1)
                    last_printed_depth = printing_depth
                elseif length(stack) > length(last_stack) || first_mismatch != nothing
                    printing_depth = min(depth, last_depth + 1)
                    last_printed_depth = printing_depth
                else
                    printing_depth = 0
                end
                stole_one = false
                if printing_depth != 0
                    for _ in 1:(printing_depth-1)
                        print(buf, "│")
                    end
                    if printing_depth <= last_depth-1 && first_mismatch === nothing
                        print(buf, "┃")
                        for _ in printing_depth+1:min(depth, last_depth)
                            print(buf, "│")
                        end
                    else
                        stole_one = true
                        print(buf, "╻")
                    end
                else
                    for _ in 1:min(depth, last_depth)
                        print(buf, "│")
                    end
                end
                print(buf, "╷"^max(0,depth-last_depth-stole_one))
                if printing_depth != 0
                    if length(stack) == printing_depth
                        loc_method = String(code.linetable[line].method)
                    else
                        loc_method = String(code.linetable[stack[printing_depth+1]].method)
                    end
                end
                loc_method = string(" "^printing_depth, loc_method)
            end
            last_stack = stack
            entry = code.linetable[line]
        end
        push!(loc_annotations, String(take!(buf)))
        push!(loc_lineno, (lineno != 0 && lineno != last_lineno) ? string(lineno) : "")
        push!(loc_methods, loc_method)
        last_line = line
        (lineno != 0) && (last_lineno = lineno)
    end
    (loc_annotations, loc_methods, loc_lineno)
end # function compute_ir_line_annotations2


# code from julia/base/compiler/ssair/show.jl  show_ir
function show_ir2(io::IO, code::IRCode, expr_type_printer=default_expr_type_printer; argnames=Symbol[], verbose_linetable=false)
    (lines, cols) = (50, 110) #displaysize(io)
    (loc_annotations, loc_methods, loc_lineno) = compute_ir_line_annotations2(code)
    max_loc_width = maximum(length(str) for str in loc_annotations)
    max_lineno_width = maximum(length(str) for str in loc_lineno)
    max_method_width = maximum(length(str) for str in loc_methods)
    used = IdSet{Int}()
    foreach(stmt->scan_ssa_use!(push!, used, stmt), code.stmts)
    if isempty(used)
        maxsize = 0
    else
        maxused = maximum(used)
        maxsize = length(string(maxused))
    end
    for idx in eachindex(code.stmts)
        stmt = code.stmts[idx]
        try
            print_node(io, idx, stmt, used, argnames, maxsize, print_typ=false)
        catch e
            print(io, "<error printing> ", e)
        end
        annotation = loc_annotations[idx]
        loc_method = loc_methods[idx]
        lineno = loc_lineno[idx]
        # @info :annotation idx annotation loc_method lineno
        method_start_column = cols - max_method_width - max_loc_width - 2
        filler = " "^(max_loc_width-length(annotation))
        printstyled(io, "\e[$(method_start_column)G$(annotation)$(filler)$(loc_method)\e[1G", color = :light_cyan) # light_black
        println(io)
    end
end # function show_ir2


import InteractiveUtils: @code_typed

function f(x)
    leaf_function(1)
    leaf_function(2)
    leaf_function(3)
    leaf_function(4)
    leaf_function(5)
end
function g()
    f(11)
    f(12)
end
h() = g()
top_function() = h()

(src,) = @code_typed top_function()
#(src,) = @code_typed first([3])
code = Core.Compiler.inflate_ir(src)::IRCode
show_ir2(stdout, code, verbose_linetable=false)
