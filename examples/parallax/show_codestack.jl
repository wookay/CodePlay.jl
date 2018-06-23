# julia -i show_codestack.jl

import InteractiveUtils: @code_typed
import Core.Compiler: IRCode
import Poptart: groupwise_codestack
import AbstractTrees: print_tree
using Millboard # table

using Bukdu # ApplicationController Changeset plug get post
using Bukdu.HTML5.Form # change form_for text_input
import Documenter.Utilities.DOM: @tags

struct IRController <: ApplicationController
    conn::Conn
end

struct CodeData
end
global changeset = Changeset(CodeData, (data="2pi",))

function layout(body)
    """
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title>@code_typed 🏂</title>
  <style>
label, input, span.prompt {
  font-size: 2em;
  font-family: Monospace;
}
span.prompt {
  color: green;
}
input {
  padding: 0.2em;
}
pre {
  font-size: 1.5em;
}
.form_submit {
  margin-left: 10px;
  font-size: 2em !important;
}
  </style>
</head>
<body>
$body
</body>
</html>
"""
end

# the example
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

function show_codestack(data)
    io = IOBuffer()
    expr = Meta.parse(data)
    if expr isa Expr
        try
            (src,) = eval(Expr(:macrocall, Symbol("@code_typed"), LineNumberNode(1, :none), expr))
            code = Core.Compiler.inflate_ir(src, Core.svec())::IRCode
            codestack = groupwise_codestack(code)
            println(io)
            println(io, table(codestack.A))
            println(io)
            print_tree(io, codestack.tree)
        catch ex
            println(io, ex)
        end
    else
        println(io, data, " is not an Expr")
    end
    String(take!(io))
end

function index(c::IRController)
    global changeset
    result = change(changeset, c.params)
    if !isempty(result.changes)
        changeset.changes = merge(changeset.changes, result.changes)
    end
    @tags div label span pre
    form1 = form_for(changeset, (IRController, post_result), method=post, multipart=true) do f
        div(
            span[:class => "prompt"]("julia> "),
            label[:for => "codedata_data"]("@code_typed "),
            text_input(f, :data, placeholder="expr", size="50"),
            " ",
            submit("🏂", class="form_submit"),
        )
    end
    body = div(form1, pre(show_codestack(changeset.changes.data)))
    render(HTML, layout(body))
end

post_result(c::IRController) = index(c)

plug(Plug.Logger, access_log=(path=normpath(@__DIR__, "access.log"),), formatter=Plug.LoggerFormatter.datetime_message)

routes(:front) do
    get("/", IRController, index)
    post("/show_ir", IRController, post_result)
end

const ServerHost = "localhost"
const ServerPort = 8080
Bukdu.start(ServerPort, host=ServerHost)
iszero(Base.JLOptions().isinteractive) && wait()
