using Oceananigans: CPU, GPU
using Oceananigans.Grids: unpack_grid

#####
##### CPU triply periodic pressure solver
#####

function TriplyPeriodicPressureSolver(::CPU, grid, pressure_bcs, planner_flag=FFTW.PATIENT)
    kx², ky², kz² = generate_discrete_eigenvalues(grid, pressure_bcs)
    wavenumbers = (kx² = kx², ky² = ky², kz² = kz²)

    # Storage for RHS and Fourier coefficients is hard-coded to be Float64
    # because of precision issues with Float32.
    # See https://github.com/climate-machine/Oceananigans.jl/issues/55
    storage = zeros(Complex{Float64}, grid.Nx, grid.Ny, grid.Nz)

    @info "Planning transforms for PressureSolver{TriplyPeriodic, CPU}..."
    x_bc, y_bc, z_bc = pressure_bcs.x.left, pressure_bcs.y.left, pressure_bcs.z.left
    FFTxyz!  =  plan_forward_transform(storage, x_bc, [1, 2, 3], planner_flag)
    IFFTxyz! = plan_backward_transform(storage, x_bc, [1, 2, 3], planner_flag)
    @info "Planning transforms for PressureSolver{TriplyPeriodic, CPU} done!"

    transforms = (FFTxyz! =  FFTxyz!, IFFTxyz! = IFFTxyz!)

    return PressureSolver(HorizontallyPeriodic(), CPU(), wavenumbers, storage, transforms, nothing)
end

function solve_poisson_equation!(solver::PressureSolver{TriplyPeriodic, CPU}, grid)
    Nx, Ny, Nz, _ = unpack_grid(grid)
    kx², ky², kz² = solver.wavenumbers.kx², solver.wavenumbers.ky², solver.wavenumbers.kz²

    # We can use the same storage for the RHS and the solution ϕ.
    RHS, ϕ = solver.storage, solver.storage

    solver.transforms.FFTxyz! * RHS  # Calculate FFTˣʸᶻ(f) in place.

    # Solve the discrete Poisson equation in spectral space. We are computing
    # the Fourier coefficients of the solution from the Fourier coefficients
    # of the RHS.
    @. ϕ = -RHS / (kx² + ky² + kz²)

    # Setting DC component of the solution (the mean) to be zero. This is also
    # necessary because the source term to the Poisson equation has zero mean
    # and so the DC component comes out to be ∞.
    ϕ[1, 1, 1] = 0

    solver.transforms.IFFTxyz! * ϕ  # Calculate IFFTˣʸᶻ(ϕ) in place.

    return nothing
end
