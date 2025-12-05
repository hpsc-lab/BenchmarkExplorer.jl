using BenchmarkTools
using Enzyme

const SUITE = BenchmarkGroup()

SUITE["basics"] = BenchmarkGroup()
SUITE["basics"]["make_zero"] = BenchmarkGroup()

p_namedtuple = (a = 1.0, b = 2.0, c = 3.0)
SUITE["basics"]["make_zero"]["namedtuple"] = @benchmarkable Enzyme.make_zero($p_namedtuple)

p_array = rand(100)
SUITE["basics"]["make_zero"]["array"] = @benchmarkable Enzyme.make_zero($p_array)

struct MyStruct
    x::Float64
    y::Float64
end
p_struct = MyStruct(1.0, 2.0)
SUITE["basics"]["make_zero"]["struct"] = @benchmarkable Enzyme.make_zero($p_struct)

SUITE["autodiff"] = BenchmarkGroup()
SUITE["autodiff"]["forward"] = BenchmarkGroup()
SUITE["autodiff"]["reverse"] = BenchmarkGroup()

f_simple(x) = sum(x .^ 2)
x_simple = rand(100)

SUITE["autodiff"]["forward"]["simple"] = @benchmarkable Enzyme.autodiff(
    Enzyme.Forward, $f_simple, Enzyme.Duplicated($x_simple, zero($x_simple))
)

SUITE["autodiff"]["reverse"]["simple"] = @benchmarkable Enzyme.autodiff(
    Enzyme.Reverse, $f_simple, Enzyme.Active, Enzyme.Duplicated($x_simple, zero($x_simple))
)

function f_complex(x)
    result = 0.0
    for i in 1:length(x)
        result += sin(x[i]) * cos(x[i])
    end
    return result
end
x_complex = rand(1000)

SUITE["autodiff"]["forward"]["complex"] = @benchmarkable Enzyme.autodiff(
    Enzyme.Forward, $f_complex, Enzyme.Duplicated($x_complex, zero($x_complex))
)

SUITE["autodiff"]["reverse"]["complex"] = @benchmarkable Enzyme.autodiff(
    Enzyme.Reverse, $f_complex, Enzyme.Active, Enzyme.Duplicated($x_complex, zero($x_complex))
)