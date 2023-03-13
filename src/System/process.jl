abstract type AbstractProcess end

struct Process <: AbstractProcess
    prefix::AbstractString
    session::AbstractBashSession

    function Process(prefix::AbstractString, session::AbstractBashSession)
        return new(prefix, session)
    end
end

# TODO: implement active process