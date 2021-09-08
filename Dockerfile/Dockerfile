FROM julia:1.6.2

RUN apt-get update -qq && apt-get install -y -qq gcc wget git

#RUN mkdir /QXContexts
#ADD . /QXContexts/

RUN git clone https://github.com/JuliaQX/QXContexts.jl.git /QXContexts
WORKDIR /QXContexts

ENV JULIA_DEPOT_PATH /opt/julia

RUN julia --project=. -e 'using Pkg; Pkg.instantiate();'

RUN julia --project=. -e 'using Pkg; Pkg.add("FileIO"); Pkg.add("ArgParse"); Pkg.add("TimerOutputs");'

RUN julia --project=. -e 'using Pkg; Pkg.build("QXContexts");'

# run tests to verify they are working and to precompile
RUN julia --project=. examples/rqc_example.jl
CMD ["julia", "--project=/QXContexts"]
