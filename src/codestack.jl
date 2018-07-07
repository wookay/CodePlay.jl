# module Poptart

import Core.Compiler: IRCode
import Base.IRShow: compute_inlining_depth, compute_loc_stack
import AbstractTrees: children, printnode, print_tree

mutable struct Node{T<:NamedTuple}
    children::Vector
    data::T
end

struct CodeStack
    A::Array{Union{Nothing,Int}}
    tree::Node{<:NamedTuple}
end

children(node::Node{<:NamedTuple}) = node.children
# printnode(io::IO, node::Node{<:NamedTuple}) = Base.printstyled(io, node.data, color=:blue)

function watering!(parent::Node{<:NamedTuple}, A::Array{Union{Nothing,Int}}, code::IRCode, maxdepth, range::UnitRange, depth)
    col = A[range, depth]
    for nt in groupwise(identity, col)
        nt.value === nothing && continue
        r = (range.start-1+nt.range.start):(range.start-1+nt.range.stop)
        line = nt.value
        entry = code.linetable[line]
        node = Node([], (value=entry, range=r))
        push!(parent.children, node)
        maxdepth != depth && watering!(node, A, code, maxdepth, r, depth+1)
    end
end

function groupwise_codestack(code::IRCode)::CodeStack    
    nts = map(eachindex(code.stmts)) do idx
        line = code.lines[idx]
        (idx=idx, line=line, depth=(line == 0 ? 1 : compute_inlining_depth(code.linetable, line)+1))
    end
    maxdepth = maximum(nt.depth for nt in nts)
    length_stmts = length(code.stmts)
    A = Array{Union{Nothing,Int}}(nothing, length_stmts, maxdepth)
    for nt in nts
        if nt.line != 0
            A[nt.idx, 1:nt.depth] = compute_loc_stack(code, nt.line)
        end
    end
    range = 1:length_stmts
    depth = 1
    root = Node{<:NamedTuple}([], (value=nothing, range=range))
    watering!(root, A, code, maxdepth, range, depth)
    CodeStack(A, root)
end

# module Poptart
