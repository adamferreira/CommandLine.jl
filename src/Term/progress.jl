# -------------------------------------------
#           Progress
# -------------------------------------------
using Dates
using Term
import Term.Progress: AbstractColumn, DescriptionColumn, SpinnerColumn, PercentageColumn, ElapsedColumn, CompletedColumn, SeparatorColumn
import Term.Progress: ProgressJob, Progress, ProgressBar
import Term.Progress: addjob!, start!, render, stop!
import Term.Segments: Segment
import Term.Measures: Measure

struct LoopingStepsColumn <: AbstractColumn
    job::ProgressJob
    segments::Vector{Segment}
    measure::Measure
    style::String
    steps::Vector{String}
    # Size (in char) if the longest step name
    maxwidth::Int

    function LoopingStepsColumn(job::ProgressJob; style::String, steps::Vector{String})
        txt = Segment(steps[1], style)
        return new(job, [txt], txt.measure, style, steps, maximum(length.(steps)))
    end
end


function Term.Progress.update!(col::LoopingStepsColumn, color::String, args...)::String
    if !col.job.finished
        txt = col.steps[col.job.i]
    else
        txt = "Done"
    end
    # Padding if the step name is shorter than longest step name
    txt = txt * " "^(col.maxwidth - length(txt))
    return Segment(txt, col.style).text
end


mutable struct DotProgressColumn <: AbstractColumn
    job::ProgressJob
    segments::Vector{Segment}
    measure::Measure
    # Status of each steps
    step_status::Vector{Symbol}
    # Used to print step status
    status_to_token::Dict{Symbol, String}
    function DotProgressColumn(job::ProgressJob)
        status_to_token = Dict(
            :todo =>    "{black bold}" * "◯" * "{/black bold}",
            :skip =>    "{black bold}" * "⬤" * "{/black bold}",
            :success => "{green bold}" * "⬤" * "{/green bold}",
            :error =>   "{red bold}"   * "⬤" * "{/red bold}",
            :running => "{blue bold}"  * "⬤" * "{/blue bold}",
        )
        init_status = [:todo for i=1:job.N]
        return new(job, Vector{Segment}(), Measure(0, 0), init_status, status_to_token)
    end
end

function Term.Progress.update!(col::DotProgressColumn, color::String, args...)::String
    line = Base.join([col.status_to_token[col.step_status[i]] for i = 1:length(col.step_status)], " ")
    return Term.apply_style(line)
end

function update_status!(col::DotProgressColumn, step::Int, status::Symbol)
    col.step_status[step] = status
end

function update_current_status!(col::DotProgressColumn, status::Symbol)
    update_status!(col, col.job.i, status)
end


mutable struct NewElapsedColumn <: AbstractColumn
    job::ProgressJob
    segments::Vector{Segment}
    measure::Measure
    style::String
    padwidth::Int
    # Total duration, stop increments if job is finished
    elapsedtime::Int64

    NewElapsedColumn(job::ProgressJob; style = TERM_THEME[].progress_elapsedcol_default) =
        new(job, [], Measure(6 + 9, 1), style, 10, 0)
end

function Term.Progress.update!(col::NewElapsedColumn, args...)::String
    isnothing(col.job.startime) && return " "^(col.measure.w)
    # Stop elapsed refresh is job is finished !
    col.elapsedtime = if col.job.finished
        col.elapsedtime # in ms
    else
        (Dates.now() - col.job.startime).value  # in ms
    end

    # format elapsed message
    msg = if col.elapsedtime < 1000
        string(col.elapsedtime, "ms")
    elseif col.elapsedtime < (60 * 1000)
        # under a minute
        string(round(col.elapsedtime / 1000; digits = 2), "s")
    else
        # show minutes
        string(round(col.elapsedtime / (60 * 1000); digits = 2), "min")
    end

    msg = lpad(Term.str_trunc(msg, col.padwidth), col.padwidth)
    return Term.apply_style("elapsed: $(msg)", col.style)
end

function Term.Progress.update2!(col::NewElapsedColumn, args...)::String
    isnothing(col.job.startime) && return " "^(col.measure.w)

    # Stop elapsed refresh is job is finished !
    col.elapsedtime = if col.job.finished
        col.elapsedtime # in ms
    else
        (Dates.now() - col.job.startime).value  # in ms
    end

    millisec = Int64(col.elapsedtime % 1000)
    hour = Int64(floor((col.elapsedtime - 0) / (1000*60*60)))
    min = Int64(floor((col.elapsedtime - hour) / (1000*60)))
    sec = Int64(((col.elapsedtime - millisec) / 1000) % 60)
    msg = "$(@sprintf("%.2i", hour))h $(@sprintf("%.2i", min))m $(@sprintf("%.2i", sec))s $(@sprintf("%.3i", millisec))ms"
    msg = lpad(Term.str_trunc(msg, col.padwidth), col.padwidth)
    return Term.apply_style("elapsed: $(msg)", col.style)
end