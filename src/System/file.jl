using FileWatching

function watch_files(paths::Vector{String}, buffering::Int64 = 1)::Base.Channel
    # Channel holding a single filepath corresponding to last non treated file change in `paths`
    file_changed = Base.Channel(1)
    # Use stdlib blocking watch in a Task per watched files
    function __watch_file(path::String)
        return @async begin
            while Base.isopen(file_changed)
                # Blocking call to stdlib watch_file
                file_event = FileWatching.watch_file(path)
                # If we arrive here, the file `path` as been updated (because no timeout is used here)
                # Put `path` is the shared channel so that it can be treated
                # This call is blocking and no further update of `path` will be treated until file_changed is empty
                if file_event.changed
                    put!(file_changed, path)
                end
                # Buffer so each file change isn't taken into account multiple times
                sleep(buffering)
            end
        end
    end

    # All created subtasks will end when `file_changed` is closed
    __watch_file.(paths)

    return file_changed
end