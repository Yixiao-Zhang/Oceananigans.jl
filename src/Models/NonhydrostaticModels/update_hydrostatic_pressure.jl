using Oceananigans.Operators: Δzᵃᵃᶜ

"""
Update the hydrostatic pressure perturbation pHY′. This is done by integrating
the `buoyancy_perturbation` downwards:

    `pHY′ = ∫ buoyancy_perturbation dz` from `z=0` down to `z=-Lz`
"""
@kernel function _update_hydrostatic_pressure!(pHY′, grid, buoyancy, C)
    i, j = @index(Global, NTuple)

    @inbounds pHY′[i, j, grid.Nz] = - ℑzᵃᵃᶠ(i, j, grid.Nz+1, grid, z_dot_g_b, buoyancy, C) * Δzᵃᵃᶠ(i, j, grid.Nz+1, grid)

    @unroll for k in grid.Nz-1 : -1 : 1
        @inbounds pHY′[i, j, k] = pHY′[i, j, k+1] - ℑzᵃᵃᶠ(i, j, k+1, grid, z_dot_g_b, buoyancy, C) * Δzᵃᵃᶠ(i, j, k+1, grid)
    end
end

function update_hydrostatic_pressure!(pHY′, arch, grid, buoyancy, tracers)
    pressure_calculation = launch!(arch, grid, :xy, _update_hydrostatic_pressure!,
                                   pHY′, grid, buoyancy, tracers,
                                   dependencies = Event(device(arch)))

    # Fill halo regions for pressure
    wait(device(model.architecture), pressure_calculation)

    return nothing
end

update_hydrostatic_pressure!(pHY′, arch, grid::AbstractGrid{<:Any, <:Any, <:Any, <:Flat}, args...) = nothing

