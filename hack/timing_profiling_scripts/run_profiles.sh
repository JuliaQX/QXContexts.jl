#!/bin/bash

NUM=1
while [ -d profiles_$NUM ]; do
    NUM=$(($NUM + 1))
done
PROF_DIR=profiles_$NUM
echo "Profile output will be written to $PROF_DIR"
mkdir $PROF_DIR
pushd $PROF_DIR

nsys launch -t cuda,nvtx julia --project=../../../ ../gpu_profiles.jl 3 

popd
