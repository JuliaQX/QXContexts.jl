# The following structure is adapted from the OpticSim.jl package @ # d492ca0

import Pkg, Libdl, PackageCompiler

function compile(sysimage_path = "JuliaSysimage.$(Libdl.dlext)")
    env_to_precompile = joinpath(@__DIR__, "..")
    precompile_execution_file = joinpath(@__DIR__, "precompile.jl")
    project_filename = joinpath(env_to_precompile, "Project.toml")
    project = Pkg.API.read_project(project_filename)
    used_packages = Symbol.(collect(keys(project.deps)))

    # Remove unneeded packages
    filter!(x -> x ∉ [:Libdl, :PackageCompiler, :Pkg], used_packages)

    @info "Creating QXContexts.jl sysimg: $(sysimage_path)"
    PackageCompiler.create_sysimage(
        used_packages,
        sysimage_path = sysimage_path,
        project = env_to_precompile,
        precompile_execution_file = precompile_execution_file
    )
end
~         
