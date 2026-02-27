function AptGet()::Package
    return Package(
        "AptGet"; requires = [],
        on_install = wsli -> begin
            RUN(wsli, "sudo apt-get upgrade -y")
            RUN(wsli, "sudo apt-get update -y")
        end
    )
end
export AptGet

function AptPackage(pname::String)
    return Package(
        pname; requires = [AptGet()],
        on_install = wsli -> begin
            RUN(wsli, "sudo apt-get install -y $(pname)")
        end,
        on_update = wsli -> begin
            RUN(wsli, "sudo apt-get install -y --only-upgrade $(pname)")
        end,
        on_delete = wsli -> begin
            RUN(wsli, "sudo apt-get purge --auto-remove $(pname)")
        end
    )
end
export AptPackage

