#!/bin/bash

# This file is used to help with precompiling Julia sysimg shared object libraries
# This follows the procedure discussed by https://julialang.github.io/PackageCompiler.jl/dev/sysimages/

#Exit on error
set -e

while getopts ":i:o:" opt; do
  case $opt in
    i) trace_file="$OPTARG"
    ;;
    o) sys_img="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ -z ${trace_file} ] || [ -z ${sys_img} ] ; then 
    echo "Please specify precompile statements file with -i and output sysimg name with -o"; 
    exit 1
else 
    echo "Using precompile file ${trace_file} and saving sysimg as ${sys_img}"; 
fi

julia --startup-file=no --project=. -e \
"using Pkg; 
Pkg.add(\"PackageCompiler\"); 
using PackageCompiler; 
using TimerOutputs;
PackageCompiler.create_sysimage([:TimerOutputs, :MPI, :TensorOperations, :QXRun, :YAML, :OMEinsum, :JLD2], 
precompile_statements_file=\"${trace_file}\", sysimage_path=\"${sys_img}\");
"
