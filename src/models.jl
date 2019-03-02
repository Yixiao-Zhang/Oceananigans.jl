mutable struct Model
    metadata::ModelMetadata
    configuration::ModelConfiguration
    boundary_conditions::BoundaryConditions
    constants::PlanetaryConstants
    eos::EquationOfState
    grid::Grid
    velocities::VelocityFields
    tracers::TracerFields
    pressures::PressureFields
    G::SourceTerms
    Gp::SourceTerms
    forcings::ForcingFields
    forcing::Forcing
    stepper_tmp::StepperTemporaryFields
    operator_tmp::OperatorTemporaryFields
    ssp  # ::SpectralSolverParameters or ::SpectralSolverParametersGPU
    clock::Clock
    output_writers::Array{OutputWriter,1}
    diagnostics::Array{Diagnostic,1}
end

"""
    Model(; kwargs...)

Construct an `Oceananigans.jl` model. The keyword arguments are:

          N (tuple) : model resolution in (x, y, z)
          L (tuple) : model domain in (x, y, z)
         dt (float) : time step
 start_time (float) : start time for the simulation
  iteration (float) : ?
         arch (sym) : architecture (:cpu or :gpu)
  float_type (type) : floating point type for model data (typically Float32 or Float64)
          constants : planetary constants (?)
                eos : equation of state to infer density from temperature and salinity
            forcing : forcing functions for (u, v, w, T, S)
boundary_conditions : boundary conditions
     output_writers : output writer
        diagonstics : diagnostics

        ... and more.
"""
function Model(;
    # Model resolution and domain size
             N,
             L,
    # Molecular parameters
             ν = 1.05e-6, νh = ν, νv = ν,
             κ = 1.43e-7, κh = κ, κv = κ,
    # Time stepping
    start_time = 0,
     iteration = 0, # ?
    # Model architecture and floating point precision
          arch = :cpu,
    float_type = Float64,
     constants = Earth(),
    # Equation of State
           eos = LinearEquationOfState(),
    # Forcing and boundary conditions for (u, v, w, T, S)
       forcing = Forcing(nothing, nothing, nothing, nothing, nothing),
    boundary_conditions = BoundaryConditions(:periodic, :periodic, :rigid_lid, :free_slip),
    # Output and diagonstics
    output_writers = OutputWriter[],
       diagnostics = Diagnostic[]
)

    # Initialize model basics.
         metadata = ModelMetadata(arch, float_type)
    configuration = ModelConfiguration(νh, νv, κh, κv)
             grid = RegularCartesianGrid(metadata, N, L)
            clock = Clock(start_time, iteration)

    # Initialize fields, including source terms and temporary variables.
      velocities = VelocityFields(metadata, grid)
         tracers = TracerFields(metadata, grid)
       pressures = PressureFields(metadata, grid)
               G = SourceTerms(metadata, grid)
              Gp = SourceTerms(metadata, grid)
        forcings = ForcingFields(metadata, grid)
     stepper_tmp = StepperTemporaryFields(metadata, grid)
    operator_tmp = OperatorTemporaryFields(metadata, grid)

    # Initialize Poisson solver.
    if metadata.arch == :cpu
        stepper_tmp.fCC1.data .= rand(metadata.float_type, grid.Nx, grid.Ny, grid.Nz)
        ssp = SpectralSolverParameters(grid, stepper_tmp.fCC1, FFTW.MEASURE; verbose=true)
    elseif metadata.arch == :gpu
        stepper_tmp.fCC1.data .= CuArray{Complex{Float64}}(rand(metadata.float_type, grid.Nx, grid.Ny, grid.Nz))
        ssp = SpectralSolverParametersGPU(grid, stepper_tmp.fCC1)
    end

    # Default initial condition
    velocities.u.data .= 0
    velocities.v.data .= 0
    velocities.w.data .= 0
    tracers.S.data .= 35
    tracers.T.data .= 283

    # Hydrostatic pressure vertical profile.
    pHY_profile = [-eos.ρ₀*constants.g*h for h in grid.zC]

    # Set hydrostatic pressure everywhere.
    if metadata.arch == :cpu
        pressures.pHY.data .= repeat(reshape(pHY_profile, 1, 1, grid.Nz), grid.Nx, grid.Ny, 1)
    elseif metadata.arch == :gpu
        pressures.pHY.data .= CuArray(repeat(reshape(pHY_profile, 1, 1, grid.Nz), grid.Nx, grid.Ny, 1))
    end

    # Calculate initial density based on tracer values.
    ρ!(eos, grid, tracers)

    Model(metadata, configuration, boundary_conditions, constants, eos, grid,
          velocities, tracers, pressures, G, Gp, forcings, forcing,
          stepper_tmp, operator_tmp, ssp, clock, output_writers, diagnostics)
end

"Legacy constructor for `Model`."
Model(N, L; arch=:cpu, float_type=Float64) = Model(N=N, L=L; arch=arch, float_type=float_type)