#!/bin/bash

#SBATCH -A tra21_hackathon
#SBATCH --time 1:00:00     # format: HH:MM:SS
#SBATCH -N 1                # 1 node
#SBATCH --ntasks-per-node=8 # 8 tasks out of 128
#SBATCH --gres=gpu:4        # 1 gpus per node out of 4
#SBATCH --exclusive
#SBATCH --mem=16000          # memory per node out of 246000MB
#SBATCH --job-name=TestProfile
#SBATCH --reservation=s_tra_hackathon21

module load profile/advanced
module load autoload julia/1.7--gnu--8.4.0

julia --project=../../ 1_timings.jl
