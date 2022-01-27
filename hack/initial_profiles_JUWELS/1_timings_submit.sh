#!/bin/bash

#SBATCH --account=prpb107
#SBATCH --time 1:00:00       # format: HH:MM:SS
#SBATCH --nodes=1            # 1 node
#SBATCH --ntasks-per-node=8  # 8 tasks out of 128
#SBATCH --gres=gpu:2         # 1 gpus per node out of 4
#SBATCH --output=mpi-out.%j
#SBATCH --error=mpi-err.%j
#SBATCH --job-name=TestProfile
#SBATCH --partition=develbooster

module load Stages/2022
module load GCC/11.2.0
module load OpenMPI/4.1.2
module load CUDA/11.5
module load Julia/1.7.0

export JULIA_MPI_BINARY=system
export JULIA_CUDA_USE_BINARYBUILDER=false

julia --project=../../ 1_timings.jl
