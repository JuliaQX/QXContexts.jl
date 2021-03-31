# Custom sysimg

Given QXRun.jl will require to compile all tensor contract paths as they are encountered, it can make sense to create a custom sysimg using PackageCompiler.jl to aid in reducing the compile time.
We have created two files for this purpose: 

- `tensor_contract_trace_generator.jl`: This file creates a large number of tensor contraction operations using the TensorOperations.jl and OMEinsum.jl packages
- `sysimage.jl`: Using the above file as determine necessary compile path, we use this file to create a sysimg named `QXRUN_JL<version number>_<CPU arch label>.<dynamic library extension>`. For Julia 1.6.0 on Skylake running Linux this will be "QXContexts_JL1.6.0_skylake.so".


To start the compilation process, run the following:
```bash
julia --project=. ./bin/sysimage.jl
```

The entire run and compilation process can take 30+ minutes.

As MPI is compiled into this systemimage library, we must launch Julia with a MPI command, be it `mpiexec`, `mpiexecjl`, or `srun` for SLURM, etc.
```bash
mpiexecjl -n 1 julia -JQXContexts_JL1.6.0_skylake.so --project=. bin/tensor_contract_trace_generator.jl

#or if explicitly using SLURM
srun -n 1 julia -JQXContexts_JL1.6.0_skylake.so --project=. bin/tensor_contract_trace_generator.jl
```

The runtime in this instance can be a few 10s of seconds.
