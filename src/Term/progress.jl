using Term.Progress: Progress
import Term.Progress: AbstractColumn, ProgressJob
import Term.Segments: Segment
import Term.Measures: Measure


struct LoopingStepsColumn <: AbstractColumn
    job::ProgressJob
    segments::Vector{Segment}
    measure::Measure
    style::String
    steps::Vector{String}

    function LoopingStepsColumn(job::ProgressJob; style::String, steps::Vector{String})
        txt = Segment(steps[1], style)
        return new(job, [txt], txt.measure, style, steps)
    end
end


function Progress.update!(col::LoopingStepsColumn, color::String, args...)::String
    txt = Segment(col.steps[col.job.i], col.style)
    return txt.text
end

mutable struct DotProgressColumn <: AbstractColumn
    job::ProgressJob
    segments::Vector{Segment}
    measure::Measure
    nsegs::Int

    DotProgressColumn(job::ProgressJob) = new(job, Vector{Segment}(), Measure(0, 0), 0)
end

function setwidth!(col::DotProgressColumn, width::Int)
    col.measure = Measure(width, 1)
    return col.nsegs = width
end

function Progress.update!(col::DotProgressColumn, color::String, args...)::String
    completed = rint(col.nsegs * col.job.i / col.job.N)
    remaining = col.nsegs - completed
    return Term.apply_style(
        "{" *
        color *
        " bold}" *
        '━'^(completed) *
        "{/" *
        color *
        " bold}" *
        " "^(remaining),
    )
end