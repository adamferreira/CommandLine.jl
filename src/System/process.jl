abstract type AbstractProcess end

struct Process <: AbstractProcess
    prefix::AbstractString
    session::AbstractBashSession

    function Process(prefix::AbstractString, session::AbstractBashSession)
        return new(prefix, session)
    end
end


struct BackgroundProcess <: AbstractProcess
    background_session::AbstractBashSession
    pid::UInt32

    function BackgroundProcess(session::AbstractBashSession, cmd)
        # Create the `run_background` macro in the session
        # Raw strings do not perform interpolation
        # `$!` gives the pid of the last command !
        stringoutput(session, raw"run_background() { eval \"$@\" &>/dev/null & disown; echo $!; }")
        strpid = stringoutput(session, "run_background \"$(cmd)\"")

        # Note: BackgroundProcess needs to be killed with pkill -P <pid>
        # To kill pid and all process that pid might spawn itself 
        return new(session, parse(UInt32, strpid))
    end
end

function kill(p::BackgroundProcess)
    stringoutput(p.background_session, "pkill -P $(p.pid)")
end