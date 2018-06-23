# module Poptart

struct PairWiseIter
    A
end

function Base.iterate(S::PairWiseIter, state=1)
    if state > length(S.A)
        nothing
    else
        ((S.A[state], lastindex(S.A) == state ? missing : S.A[state+1]), state+1)
    end
end

pairwise(A) = PairWiseIter(A)

function groupwise(f, A::Vector{T}) where T
    G = []
    S = Dict{T,UnitRange}()
    keyorder = []
    for (i, (a, b)) in enumerate(pairwise(A))
        if haskey(S, a)
            S[a] = S[a].start:i
        else
            S[a] = i:i
            push!(keyorder, a)
        end
        if missing === b || f(a) != f(b)
            push!(G, map(a -> (value=a, range=S[a]), keyorder)...)
            empty!(S)
            empty!(keyorder)
        end
    end
    G
end

# module Poptart
