using Test
import Poptart: groupwise

@test groupwise(identity, [1,5,5,5]) == [(value=1, range=1:1), (value=5, range=2:4)]
