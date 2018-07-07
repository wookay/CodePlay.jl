# julia -i show_codestack.jl

# Demo for Poptart.jl
#   https://github.com/wookay/Poptart.jl

# Visit to build on Heroku
#   https://github.com/wookay/heroku-codetyped


import InteractiveUtils: @code_typed
import Core.Compiler: IRCode
import Poptart
import AbstractTrees: print_tree, printnode
using Millboard # table
using DataLogger

using Bukdu # ApplicationController Changeset plug get post
using Bukdu.HTML5.Form # change form_for text_input
import Documenter.Utilities.DOM: @tags

struct IRController <: ApplicationController
    conn::Conn
end

struct CodeData
end

function layout(body)
    """
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title>@code_typed 🏂</title>
  <style>
label, input, span.prompt {
    font-size: 1.6em;
    font-family: Monospace;
}
span.prompt {
    color: green;
}
input {
    padding: 0.2em;
}
pre {
    font-size: 1.3em;
}
.form_submit {
    margin-left: 10px;
    font-size: 2em !important;
}
div#examples {
    padding-bottom: 10px;
}
a.example {
    padding-left: 20px;
    text-decoration: none;
}
  </style>
  <script>
function clicked_example(data) {
    document.getElementById('codedata_data').value = data;
}
  </script>
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

function printnode(io::IO, node::Poptart.Node{<:NamedTuple})
    entry = node.data.value
    if entry === nothing
        Base.printstyled(io, "🌲")
    else
        Base.printstyled(io, entry.method, color=:blue)
    end
end

function show_codestack(data)
    io = IOBuffer()
    expr = Meta.parse(data)
    if expr isa Expr
        try
            (src,) = eval(Expr(:macrocall, Symbol("@code_typed"), LineNumberNode(1, :none), expr))
            code = Core.Compiler.inflate_ir(src)::IRCode
            codestack = Poptart.groupwise_codestack(code)
            println(io)
            println(io, code)
            println(io)
            print_tree(io, codestack.tree)
            println(io)
            println(io, table(codestack.A))
        catch ex
            println(io, ex)
        end
    else
        println(io, data, " is not an Expr")
    end
    String(take!(io))
end

function index(c::IRController, show_banner=true)
    changeset = Changeset(CodeData, (data="2pi",)) # to be global
    result = change(changeset, c.params)
    if !isempty(result.changes)
        changeset.changes = merge(changeset.changes, result.changes)
    end
    @tags div label span pre a ul li
    form1 = form_for(changeset, (IRController, post_result), method=post, multipart=true) do f
        div(
            span[:class => "prompt"]("julia> "),
            label[:for => "codedata_data"]("@code_typed "),
            text_input(f, :data, placeholder="expr", size="50"),
            " ",
            submit("🏂", class="form_submit"),
        )
    end
    top = div(a[:href => "/"]("Poptart"))
    banner_help = show_banner ? div(
        pre(DataLogger.read_stdout(Base.banner)),
        div[:id => "examples"](
            span("Examples:"),
            div(a[:class => "example", :href => "#", :onclick => """clicked_example('2pi')"""]("""2pi""")),
            div(a[:class => "example", :href => "#", :onclick => """clicked_example('length("abc")')"""]("""length("abc")""")),
            div(a[:class => "example", :href => "#", :onclick => """clicked_example('sin(deg2rad(90))')"""]("""sin(deg2rad(90))""")),
        )
    ) : ""
    source_link = div(a[:href => "https://github.com/wookay/Poptart.jl/blob/master/examples/parallax/show_codestack.jl"]("source code"))
    body = div(top, banner_help, form1, pre(show_codestack(changeset.changes.data)), source_link)
    render(HTML, layout(body))
end

index(c::IRController) = index(c, true) 
post_result(c::IRController) = index(c, false)

plug(Plug.Logger, access_log=(path=normpath(@__DIR__, "access.log"),), formatter=Plug.LoggerFormatter.datetime_message)

routes(:front) do
    get("/", IRController, index)
    post("/show_codestack", IRController, post_result)
end

# pre-loading
Router.call(get, "/")
Router.call(post, "/show_codestack")

if haskey(ENV, "ON_HEROKU")
    import Sockets: IPv4
    Bukdu.start(parse(Int, ENV["PORT"]); host=IPv4(0,0,0,0))
else
    const ServerHost = "localhost"
    const ServerPort = 8080
    Bukdu.start(ServerPort, host=ServerHost)
end
iszero(Base.JLOptions().isinteractive) && wait()
