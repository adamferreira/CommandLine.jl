abstract type AbstractProcess end

struct Process <: AbstractProcess
    prefix::AbstractString
    session::AbstractBashSession

    function Process(prefix::AbstractString, session::AbstractBashSession)
        return new(prefix, session)
    end
end


struct ActiveProcess <: AbstractProcess
    running_session::AbstractBashSession
    pids::Vector{UInt32}

    function ActiveProcess(template::AbstractBashSession, cmd)
        # Clone the template to run `cmd` inside the clone
        clone = CommandLine.clone(template)
        # Run `cmd` as a foreground process in the clone
        CommandLine.stringoutput(clone, cmd)
    end
end


# struct BackgroundProcess <: AbstractProcess
# end