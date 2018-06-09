import Core: CodeInfo, PhiNode, PhiCNode, PiNode, UpsilonNode, SSAValue
import Core.Compiler: Params, CodeInfo, InferenceState, InferenceResult, IRCode, ReturnNode, GotoIfNot, Argument
import Core.Compiler: scan_ssa_use!, isexpr
import Base: IdSet, sourceinfo_slotnames
import Base.IRShow: compute_ir_line_annotations, compute_inlining_depth, compute_loc_stack, should_print_ssa_type, default_expr_type_printer


# code from julia/base/compiler/ssair/show.jl  print_ssa
print_ssa2(io::IO, val::SSAValue, argnames) = Base.printstyled(io, "%$(val.id)", color = :red)
print_ssa2(io::IO, val::Argument, argnames) = Base.printstyled(io, isempty(argnames) ? "%%$(val.n)" : "%%$(argnames[val.n])", color = :green)
print_ssa2(io::IO, val::GlobalRef, argnames) = Base.printstyled(io, val, color = 203)
print_ssa2(io::IO, @nospecialize(val), argnames) = Base.printstyled(io, val, color = 213)


# code from julia/base/compiler/ssair/show.jl  print_node
function print_node2(io::IO, idx, stmt, used, argnames, maxsize; color = true, print_typ=true)
    if idx in used
        pad = " "^(maxsize-length(string(idx)))
        Base.print(io, "%$idx $pad= ")
    else
        Base.print(io, " "^(maxsize+4))
    end
    if isa(stmt, PhiNode)
        args = map(1:length(stmt.edges)) do i
            e = stmt.edges[i]
            v = !isassigned(stmt.values, i) ? "#undef" :
                sprint() do io′
                    print_ssa2(io′, stmt.values[i], argnames)
                end
            "$e => $v"
        end
        Base.print(io, "φ ", '(', join(args, ", "), ')')
    elseif isa(stmt, PhiCNode)
        Base.print(io, "φᶜ ", '(', join(map(x->sprint(print_ssa2, x, argnames), stmt.values), ", "), ')')
    elseif isa(stmt, PiNode)
        Base.print(io, "π (")
        print_ssa2(io, stmt.val, argnames)
        Base.print(io, ", ")
        if color
            Base.printstyled(io, stmt.typ, color=:cyan)
        else
            Base.print(io, stmt.typ)
        end
        Base.print(io, ")")
    elseif isa(stmt, UpsilonNode)
        Base.print(io, "ϒ (")
        isdefined(stmt, :val) ?
            print_ssa2(io, stmt.val, argnames) :
            Base.print(io, "#undef")
        Base.print(io, ")")
    elseif isa(stmt, ReturnNode)
        if !isdefined(stmt, :val)
            Base.print(io, "unreachable")
        else
            Base.print(io, "return ")
            print_ssa2(io, stmt.val, argnames)
        end
    elseif isa(stmt, GotoIfNot)
        Base.print(io, "goto ", stmt.dest, " if not ")
        print_ssa2(io, stmt.cond, argnames)
    elseif isexpr(stmt, :call)
        print_ssa2(io, stmt.args[1], argnames)
        Base.print(io, "(")
        Base.print(io, join(map(arg->sprint(io->print_ssa2(io, arg, argnames)), stmt.args[2:end]), ", "))
        Base.print(io, ")")
        if print_typ && stmt.typ !== Any
            Base.print(io, "::$(stmt.typ)")
        end
    elseif isexpr(stmt, :invoke)
        print(io, "invoke ")
        linfo = stmt.args[1]
        print_ssa2(io, stmt.args[2], argnames)
        Base.print(io, "(")
        sig = linfo.specTypes === Tuple ? () : Base.unwrap_unionall(linfo.specTypes).parameters
        print_arg(i) = sprint() do io
            print_ssa2(io, stmt.args[2+i], argnames)
            if (i + 1) <= length(sig)
                print(io, "::$(sig[i+1])")
            end
        end
        Base.print(io, join((print_arg(i) for i=1:(length(stmt.args)-2)), ", "))
        Base.print(io, ")")
        if print_typ && stmt.typ !== Any
            Base.print(io, "::$(stmt.typ)")
        end
    elseif isexpr(stmt, :new)
        Base.print(io, "new(")
        Base.print(io, join(String[sprint(io->print_ssa2(io, arg, argnames)) for arg in stmt.args], ", "))
        Base.print(io, ")")
    else
        Base.print(io, stmt)
    end
end


# code from julia/base/compiler/ssair/show.jl  show_ir
function show_ir2(io::IO, code::IRCode, expr_type_printer=default_expr_type_printer; argnames=Symbol[], verbose_linetable=false)
    (lines, cols) = displaysize(io)
    used = IdSet{Int}()
    foreach(stmt->scan_ssa_use!(push!, used, stmt), code.stmts)
    cfg = code.cfg
    max_bb_idx_size = length(string(length(cfg.blocks)))
    bb_idx = 1
    if any(i->!isassigned(code.new_nodes, i), 1:length(code.new_nodes))
        printstyled(io, :red, "ERROR: New node array has unset entry\n")
    end
    new_nodes = code.new_nodes[filter(i->isassigned(code.new_nodes, i), 1:length(code.new_nodes))]
    foreach(nn -> scan_ssa_use!(push!, used, nn.node), new_nodes)
    perm = sortperm(new_nodes, by = x->x.pos)
    new_nodes_perm = Iterators.Stateful(perm)

    if isempty(used)
        maxsize = 0
    else
        maxused = maximum(used)
        maxsize = length(string(maxused))
    end
    if !verbose_linetable
        (loc_annotations, loc_methods, loc_lineno) = compute_ir_line_annotations(code)
        max_loc_width = maximum(length(str) for str in loc_annotations)
        max_lineno_width = maximum(length(str) for str in loc_lineno)
        max_method_width = maximum(length(str) for str in loc_methods)
    end
    max_depth = maximum(line == 0 ? 1 : compute_inlining_depth(code.linetable, line) for line in code.lines)
    last_stack = []
    for idx in eachindex(code.stmts)
        if !isassigned(code.stmts, idx)
            # This is invalid, but do something useful rather
            # than erroring, to make debugging easier
            printstyled(io, :red, "UNDEF\n")
            continue
        end
        stmt = code.stmts[idx]
        # Compute BB guard rail
        bbrange = cfg.blocks[bb_idx].stmts
        bbrange = bbrange.first:bbrange.last
        bb_pad = max_bb_idx_size - length(string(bb_idx))
        bb_start_str = string("$(bb_idx) ",length(cfg.blocks[bb_idx].preds) <= 1 ? "─" : "┄",  "─"^(bb_pad)," ")
        bb_guard_rail_cont = string("│  "," "^max_bb_idx_size)
        if idx == first(bbrange)
            bb_guard_rail = bb_start_str
        else
            bb_guard_rail = bb_guard_rail_cont
        end
        # Print linetable information
        if verbose_linetable
            stack = compute_loc_stack(code, code.lines[idx])
            # We need to print any stack frames that did not exist in the last stack
            ndepth = max(1, length(stack))
            rail = string(" "^(max_depth+1-ndepth), "│"^ndepth)
            start_column = cols - max_depth - 10
            for (i, x) in enumerate(stack)
                if i > length(last_stack) || last_stack[i] != x
                    entry = code.linetable[x]
                    printstyled(io, "\e[$(start_column)G$(rail)\e[1G", color = :light_green) # light_black
                    printstyled(io, bb_guard_rail, color = :magenta)
                    ssa_guard = " "^(maxsize+4+(i-1))
                    entry_label = "$(ssa_guard)$(entry.method) at $(entry.file):$(entry.line) "
                    hline = string("─"^(start_column-length(entry_label)-length(bb_guard_rail)+max_depth-i), "┐")
                    printstyled(io, string(entry_label, hline), "\n"; color=:light_blue) # light_black
                    bb_guard_rail = bb_guard_rail_cont
                end
            end
            printstyled(io, "\e[$(start_column)G$(rail)\e[1G", color = :light_yellow) # light_black
            last_stack = stack
        else
            annotation = loc_annotations[idx]
            loc_method = loc_methods[idx]
            lineno = loc_lineno[idx]
            # Print location information right aligned. If the line below is too long, it'll overwrite this,
            # but that's what we want.
            if get(io, :color, false)
                method_start_column = cols - max_method_width - max_loc_width - 2
                filler = " "^(max_loc_width-length(annotation))
                printstyled(io, "\e[$(method_start_column)G$(annotation)$(filler)$(loc_method)\e[1G", color = :light_blue) # light_black
            end
            printstyled(io, lineno, " "^(max_lineno_width-length(lineno)+1); color = :green, bold = true) # light_black
        end
        idx != last(bbrange) && Base.printstyled(io, bb_guard_rail, color = :light_black)
        print_sep = false
        if idx == last(bbrange)
            print_sep = true
        end
        floop = true
        while !isempty(new_nodes_perm) && new_nodes[peek(new_nodes_perm)].pos == idx
            node_idx = popfirst!(new_nodes_perm)
            new_node = new_nodes[node_idx]
            node_idx += length(code.stmts)
            if print_sep
                if floop
                    Base.printstyled(io, bb_start_str, color = :cyan)
                else
                    Base.print(io, "│  "," "^max_bb_idx_size)
                end
            end
            print_sep = true
            floop = false
            Base.with_output_color(:yellow, io) do io′
                print_node(io′, node_idx, new_node.node, used, argnames, maxsize; color = false, print_typ=false)
            end
            if should_print_ssa_type(new_node.node) && node_idx in used
                expr_type_printer(io, new_node.typ)
            end
            Base.println(io)
        end
        if print_sep
            if idx == first(bbrange) && floop
                Base.printstyled(io, bb_start_str, color = :light_black)
            else
                Base.printstyled(io, idx == last(bbrange) ? string("└", "─"^(1+max_bb_idx_size), " ") :
                    string("│  ", " "^max_bb_idx_size), color = :light_magenta)
            end
        end
        if idx == last(bbrange)
            bb_idx += 1
        end
        if !isassigned(code.types, idx)
            # Again, this is an error, but can happen if passes don't update their type information
            printstyled(io, "::UNDEF", color=:red)
            println(io)
            continue
        end
        typ = code.types[idx]
        try
            print_node2(io, idx, stmt, used, argnames, maxsize, print_typ=false)
        catch e
            print(io, "<error printing> ", e)
        end
        if should_print_ssa_type(stmt) && idx in used
            expr_type_printer(io, typ)
        end
        println(io)
    end
end


import InteractiveUtils: @code_typed
(src,) = @code_typed first([3])
#(src,) = @code_typed 2pi
code = Core.Compiler.inflate_ir(src)::IRCode
show_ir2(stdout, code, verbose_linetable=false)
println()
show_ir2(stdout, code, verbose_linetable=true)
