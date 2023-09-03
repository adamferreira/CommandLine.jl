import CommandLine as CLI
using BenchmarkTools

s = CLI.LocalGitBash()

macro printbenchmark(title, f)
    return quote
        trial = @benchmark $f()
        Base.println($title)
        Base.show(stdout, MIME("text/plain"), trial)
        Base.println()
    end
end

function create()
    _s = CLI.LocalGitBash()
    close(_s)
end

function env_vars()
    s["CL_USER"] = "CommandLine"
    s["CL_DIR"] = CLI.pwd(s) * "/" * "tmpdir"
end

function filesystem()
    CLI.mkdir(s, s["CL_DIR"])
    @assert CLI.isdir(s, s["CL_DIR"])
    #CLI.indir(s, s["CL_DIR"]) do 
    #    a = 5
    #end
    CLI.rm(s, s["CL_DIR"], "-r")
    @assert !CLI.isdir(s, s["CL_DIR"])
end

# Call the methos to compile them and ensure they do not raised
create()
env_vars()
filesystem()


@printbenchmark("LocalGitBash instanciation", create)
@printbenchmark("Environnent variables setting", env_vars)
@printbenchmark("Filesystem actions", filesystem)

# Before optimization:
"""
LocalGitBash instanciation
BenchmarkTools.Trial: 157 samples with 1 evaluation.
 Range (min … max):  30.925 ms …  37.083 ms  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     31.666 ms               ┊ GC (median):    0.00%
 Time  (mean ± σ):   31.898 ms ± 810.511 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

      ▃▁█  ▂▄▂▃▃   ▃▄
  ▆▃▆▁███▄██████▆▇▇███▄▃▁▆▄▃▆▆▇▃▁▄▄▄▁▆▁▄▁▃▄▄▃▃▁▁▃▃▁▃▁▃▁▁▁▁▁▁▁▃ ▃
  30.9 ms         Histogram: frequency by time         34.1 ms <

 Memory estimate: 64.55 KiB, allocs estimate: 912.
Environnent variables setting
BenchmarkTools.Trial: 7098 samples with 1 evaluation.
 Range (min … max):  654.300 μs …  4.307 ms  ┊ GC (min … max): 0.00% … 82.68%
 Time  (median):     678.850 μs              ┊ GC (median):    0.00%
 Time  (mean ± σ):   700.556 μs ± 87.934 μs  ┊ GC (mean ± σ):  0.14% ±  1.37%

   ▃▇██▇▅▄▄▃▂▂▂▁▁▁▁▁      ▁                                    ▂
  ▇███████████████████████████▆█▇▇█▇▇▅▆▇▇▆▅▆▆▆▆▅▅▅▅▄▄▅▅▄▂▃▅▄▃▅ █
  654 μs        Histogram: log(frequency) by time       980 μs <

 Memory estimate: 16.61 KiB, allocs estimate: 297.
Filesystem actions
BenchmarkTools.Trial: 190 samples with 1 evaluation.
 Range (min … max):  25.021 ms … 55.551 ms  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     26.027 ms              ┊ GC (median):    0.00%
 Time  (mean ± σ):   26.323 ms ±  2.250 ms  ┊ GC (mean ± σ):  0.00% ± 0.00%

         ▁▇▁▁ ▅▂█▃▁▄
  ▆▁▆▅▃▇█████████████▅██▆▆▄▄█▇▅▄▄▃▃▁▃▅▃▄▃▁▁▃▃▁▁▁▁▁▁▁▁▁▁▁▁▁▃▁▄ ▃
  25 ms           Histogram: frequency by time          29 ms <

 Memory estimate: 48.34 KiB, allocs estimate: 876.
"""

# After pass 1 (34356ac94a2ded29bbc9578400c274c035492a1f):
"""
LocalGitBash instanciation
BenchmarkTools.Trial: 159 samples with 1 evaluation.
 Range (min … max):  30.676 ms …  35.001 ms  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     31.425 ms               ┊ GC (median):    0.00%
 Time  (mean ± σ):   31.511 ms ± 557.008 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

          ▂ ▅▆▅ █ ▂ ▃ ▅▃█
  ▅▄▁▅█▇▇▄█▇███▇█▅█▄█▅████▇▄▇▇█▄▇▅▇▇█▄▅▄▅▄█▄▇▁█▄▁▄▄▅▁▁▄▁▁▁▄▁▁▄ ▄
  30.7 ms         Histogram: frequency by time         32.8 ms <

 Memory estimate: 64.08 KiB, allocs estimate: 904.
Environnent variables setting
BenchmarkTools.Trial: 7208 samples with 1 evaluation.
 Range (min … max):  619.800 μs …  4.104 ms  ┊ GC (min … max): 0.00% … 86.27%
 Time  (median):     673.200 μs              ┊ GC (median):    0.00%
 Time  (mean ± σ):   690.441 μs ± 92.902 μs  ┊ GC (mean ± σ):  0.14% ±  1.42%

  ▂▆▆▄▂▁▂▇█▆▅▃▃▂▂▁▁▁ ▁  ▁  ▁                                   ▂
  █████████████████████████████▇▇▇██▇▇█▇▆▇▇█▅▇▅▇▆▆▆▄▄▆▅▆▅▅▅▄▄▄ █
  620 μs        Histogram: log(frequency) by time         1 ms <

 Memory estimate: 16.58 KiB, allocs estimate: 296.
Filesystem actions
BenchmarkTools.Trial: 192 samples with 1 evaluation.
 Range (min … max):  24.594 ms …  29.166 ms  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     25.840 ms               ┊ GC (median):    0.00%
 Time  (mean ± σ):   26.034 ms ± 888.679 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

       ▃▅██▃▂▂▅ ▆▅▃▂▅▆  ▅▂▃   ▃  ▂   ▂
  ▄▁▇▁▁███████████████▄████▇█▇█▇▄██▁▇█▅▅▅▇▄▁▄▅▄▄▁▄▄▅▅▅▇▁▁▁▁▁▁▄ ▄
  24.6 ms         Histogram: frequency by time         28.5 ms <

 Memory estimate: 48.28 KiB, allocs estimate: 871.
"""
