# Concrete algorithm implementations.
include("support/helper.jl")
include("support/resample.jl")
# @suppress_err begin
  include("support/distributions.jl")
# end
include("support/hmc_core.jl")
include("support/adapt.jl")
include("support/init.jl")
@init @require Stan="682df890-35be-576f-97d0-3d8c8b33a550" include("support/stan-interface.jl")
include("hmcda.jl")
include("nuts.jl")
include("sghmc.jl")
include("sgld.jl")
include("hmc.jl")
include("mh.jl")
include("is.jl")
include("smc.jl")
include("pgibbs.jl")
include("pmmh.jl")
include("ipmcmc.jl")
include("gibbs.jl")

## Fallback functions

# utility funcs for querying sampler information
require_gradient(spl::Sampler) = false
require_particles(spl::Sampler) = false

assume(spl::Sampler, dist::Distribution) =
  error("[assume]: unmanaged inference algorithm: $(typeof(spl))")

observe(spl::Sampler, weight::Float64) =
  error("[observe]: unmanaged inference algorithm: $(typeof(spl))")

## Default definitions for assume, observe, when sampler = nothing.
assume(spl::Nothing, dist::Distribution, vn::VarName, vi::VarInfo) = begin
  if haskey(vi, vn)
    r = vi[vn]
  else
    r = init(dist)
    push!(vi, vn, r, dist, 0)
  end
  # NOTE: The importance weight is not correctly computed here because
  #       r is genereated from some uniform distribution which is different from the prior
  # acclogp!(vi, logpdf_with_trans(dist, r, istrans(vi, vn)))
  r, logpdf_with_trans(dist, r, istrans(vi, vn))
end

assume(spl::Nothing, dists::Vector{T}, vn::VarName, var::Any, vi::VarInfo) where T<:Distribution = begin
  @assert length(dists) == 1 "[assume] Turing only support vectorizing i.i.d distribution"
  dist = dists[1]
  n = size(var)[end]

  vns = map(i -> copybyindex(vn, "[$i]"), 1:n)

  if haskey(vi, vns[1])
    rs = vi[vns]
  else
    rs = init(dist, n)

    if isa(dist, UnivariateDistribution) || isa(dist, MatrixDistribution)
      for i = 1:n
        push!(vi, vns[i], rs[i], dist, 0)
      end
      @assert size(var) == size(rs) "[assume] variable and random number dimension unmatched"
      var = rs
    elseif isa(dist, MultivariateDistribution)
      for i = 1:n
        push!(vi, vns[i], rs[:,i], dist, 0)
      end
      if isa(var, Vector)
        @assert length(var) == size(rs)[2] "[assume] variable and random number dimension unmatched"
        for i = 1:n
          var[i] = rs[:,i]
        end
      elseif isa(var, Matrix)
        @assert size(var) == size(rs) "[assume] variable and random number dimension unmatched"
        var = rs
      else
        error("[Turing] unsupported variable container")
      end
    end
  end

  # acclogp!(vi, sum(logpdf_with_trans(dist, rs, istrans(vi, vns[1]))))

  var, sum(logpdf_with_trans(dist, rs, istrans(vi, vns[1])))
end

observe(spl::Nothing, dist::Distribution, value::Any, vi::VarInfo) = begin
  vi.num_produce += 1
  # acclogp!(vi, logpdf(dist, value))
  logpdf(dist, value)
end

observe(spl::Nothing, dists::Vector{T}, value::Any, vi::VarInfo) where T<:Distribution = begin
  @assert length(dists) == 1 "[observe] Turing only support vectorizing i.i.d distribution"
  dist = dists[1]
  @assert isa(dist, UnivariateDistribution) || isa(dist, MultivariateDistribution) "[observe] vectorizing matrix distribution is not supported"
  if isa(dist, UnivariateDistribution)  # only univariate distributions support broadcast operation (logpdf.) by Distributions.jl
    # acclogp!(vi, sum(logpdf.(Ref(dist), value)))
    sum(logpdf.(Ref(dist), value))
  else
    # acclogp!(vi, sum(logpdf(dist, value)))
    sum(logpdf(dist, value))
  end
end
