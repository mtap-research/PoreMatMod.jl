# findreplace.jl


## libraries and imports for extension
using StatsBase, LightGraphs, Xtals, MetaGraphs
import Base.(∈), Base.show


## Structs
"""
    Query(xtal, s_moty)

Stores the `Crystal` inputs used to generate a `Search`
"""
struct Query
    parent::Crystal
    s_moty::Crystal
end

Base.show(io::IO, q::Query) = print(io, q.s_moty.name, " ∈ ", q.parent.name)

"""
    Search(query, results)

Stores the `Query` used for a substructure search, and the results `DataFrame`
returned by carrying out the search.  Results are grouped by location in the
parent `Crystal` and can be examined using `nb_isomorphisms`, `nb_locations`,
and `nb_configs_at_loc`.  Subgraph isomorphisms are encoded like

    `isom = [7, 21, 9]`

where `isom[i]` is the index of the atom in `search.query.parent` corresponding
to atom `i` in `search.query.s_moty` for the location and orientation specific
to `isom`.
"""
struct Search
    query::Query # the search query (s-moty ∈ parent)
    results
end

Base.show(io::IO, s::Search) = begin
    println(io, s.query)
    print(io, nb_isomorphisms(s), " hits in ", nb_locations(s), " locations.")
end


## Helpers
@doc raw"""
    nb_isomorphisms(search::Search)

Returns the number of isomorphisms found in the specified `Search`

# Arguments
- `search::Search` a substructure `Search` object
"""
function nb_isomorphisms(search::Search)::Int
    return sum([size(grp, 1) for grp in search.results])
end


@doc raw"""
    nb_locations(search::Search)

Returns the number of unique locations (collections of atoms) at which the
specified `Search` results contain isomorphisms.

# Arguments
- `search::Search` a substructure `Search` object
"""
function nb_locations(search::Search)::Int
    return length([size(grp, 1) for grp in search.results])
end


@doc raw"""
    nb_configs_at_loc(search)

Returns a array containing the number of isomorphic configurations at a given
location (collection of atoms) for which the specified `Search` results
contain isomorphisms.

# Arguments
- `search::Search` a substructure `Search` object
"""
function nb_configs_at_loc(search::Search)::Array{Int}
    return [size(grp, 1) for grp in search.results]
end


# Retuns the geometric center of an Array, Frac/Atoms object, or Crystal.
function geometric_center(xf::Array{Float64,2})::Array{Float64}
    return sum(xf, dims=2)[:] / size(xf, 2)
end

geometric_center(coords::Frac)::Array{Float64} = geometric_center(coords.xf)

geometric_center(atoms::Atoms)::Array{Float64} = geometric_center(atoms.coords)

geometric_center(xtal::Crystal)::Array{Float64} = geometric_center(xtal.atoms)


# extension of infix `in` operator for expressive searching
# this allows all of the following:
#    s ∈ g                    →    find the moiety in the crystal
#    [s1, s2] .∈ [g]            →    find each moiety in a crystal
#    s .∈ [g1, g2]            →    find the moiety in each crystal
#    [s1, s2] .∈ [g1, g2]    →    find each moiety in each crystal
(∈)(s::Crystal, g::Crystal) = substructure_search(s, g)
# and some more like that for doing find-replace operations in one line
# these are objectively unnecessary, but fun.
(∈)(pair::Pair{Crystal, Crystal}, xtal::Crystal) =
    find_replace((pair[1] ∈ xtal), pair[2], rand_all=true)
(∈)(tuple::Tuple{Pair, Int}, xtal::Crystal) =
    find_replace(tuple[1][1] ∈ xtal, tuple[1][2], nb_loc=tuple[2])
(∈)(tuple::Tuple{Pair, Array{Int}}, xtal::Crystal) =
    find_replace(tuple[1][1] ∈ xtal, tuple[1][2], loc=tuple[2])
(∈)(tuple::Tuple{Pair, Array{Int}, Array{Int}}, xtal::Crystal) =
    find_replace(tuple[1][1] ∈ xtal, tuple[1][2], loc=tuple[2], ori=tuple[3])


# Helper for making .xyz's
write_xyz(xtal::Crystal, name::String) = Xtals.write_xyz(Cart(xtal.atoms, xtal.box), name)


# Translates all atoms in xtal such that xtal[1] is in its original position
# and the rest of xtal is in its nearest-image position relative to xtal[1]
function adjust_for_pb!(xtal::Crystal)
    # record position vector of xtal[1]
    origin_offset = deepcopy(xtal.atoms.coords.xf[:, 1])
    # loop over atom indices and correct coordinates
    for i in 1:xtal.atoms.n
        # move atoms near the origin for nearest-image calculation
        dxf = xtal.atoms.coords.xf[:, i] .- origin_offset
        # nearest_image! expects points to be within same or adjacent unit cells
        @assert all(abs.(dxf) .< 2) "Invalid xf coords in $(xtal.name)"
        # resolve periodic boundaries (other vectors unchanged)
        nearest_image!(dxf)
        # return atoms to their [nearest-image] original positions
        xtal.atoms.coords.xf[:, i] = dxf .+ origin_offset
    end
end


# Performs orthogonal Procrustes on correlated point clouds A and B
function orthogonal_procrustes(A::Array{Float64,2},
        B::Array{Float64,2})::Array{Float64,2}
    # solve the SVD
    F = svd(A * B')
    # return rotation matrix
    return F.V * F.U'
end


# Gets the s_moty-to-xtal rotation matrix
function s2p_op(s_moty::Crystal, xtal::Crystal)::Array{Float64,2}
    # s_moty in Cartesian
    A = s_moty.box.f_to_c * s_moty.atoms.coords.xf
    # parent subset in Cartesian
    B = xtal.box.f_to_c * xtal.atoms.coords.xf
    # get rotation matrix
    return orthogonal_procrustes(A, B)
end


# Gets the r_moty-to-s_mask rotation matrix
function r2m_op(r_moty::Crystal, s_moty::Crystal, m2r_isomorphism::Array{Int},
        s_mask_atoms::Atoms)::Array{Float64,2}
    if m2r_isomorphism == Int[]
        return Matrix{Int}(I, 3, 3) # if no actual isom, skip OP and return identity
    end
    # r_moty subset in Cartesian
    A = r_moty.box.f_to_c * r_moty.atoms[m2r_isomorphism].coords.xf
    # s_mask in Cartesian
    B = s_moty.box.f_to_c * s_mask_atoms.coords.xf
    # get rotation matrix
    return orthogonal_procrustes(A, B)
end


# Transforms r_moty according to two rotation matrices and a translational offset
function xform_r_moty(r_moty::Crystal, rot_r2m::Array{Float64,2},
        rot_s2p::Array{Float64,2}, xtal_offset::Array{Float64},
        xtal::Crystal)::Crystal
    # put r_moty into cartesian space
    atoms = Atoms{Cart}(length(r_moty.atoms.species), r_moty.atoms.species,
        Cart(r_moty.atoms.coords, r_moty.box))
    # transformation 1: rotate r_moty to align with s_moty
    atoms.coords.x[:,:] = rot_r2m * atoms.coords.x
    # transformation 2: rotate to align with xtal_subset
    atoms.coords.x[:,:] = rot_s2p * atoms.coords.x
    # transformation 3: translate to align with original xtal center
    atoms.coords.x .+= xtal.box.f_to_c * xtal_offset
    # cast atoms back to Frac
    xrm = Crystal(r_moty.name, xtal.box, Atoms{Frac}(length(atoms.species),
        atoms.species, Frac(atoms.coords, xtal.box)), Charges{Frac}(0))
    # restore bonding network
    for e in edges(r_moty.bonds)
        add_edge!(xrm.bonds, src(e), dst(e))
    end
    return xrm
end


# shifts coordinates to make the geometric center of the point cloud coincident
# w/ the origin
function center_on_self!(xtal::Crystal)
    xtal.atoms.coords.xf .-= geometric_center(xtal)
end


# returns an Array containing the indices
function idx_filter(xtal::Crystal, subset::Array{Int})::Array{Int,1}
    return [i for i in 1:xtal.atoms.n if !(i ∈ subset)]
end


# tracks which bonds need to be made between the parent and array
# of transformed r_moty's (xrms) along with the new fragments
function accumulate_bonds!(bonds::Array{Tuple{Int,Int}}, s2p_isom::Array{Int},
        parent::Crystal, m2r_isom::Union{Array{Int},Nothing}, xrm::Union{Crystal,Nothing}, count_xrms::Int)
    # skip bond accumulation for null replacement
    if m2r_isom == Int[] || isnothing(m2r_isom)
        return
    end
    # bonds between new fragments and parent
    # loop over s2p_isom
    for (s, p) in enumerate(s2p_isom)
        # in case the replacement moiety is smaller than the search moiety
        if s > length(m2r_isom)
            break
        end
        # find neighbors of parent_subset atoms
        n = LightGraphs.neighbors(parent.bonds, p)
        # loop over neighbors
        for nᵢ in n
            # if neighbor not in s2p_isom, must bond it to r_moty replacement
            # of parent_subset atom
            if !(nᵢ ∈ s2p_isom)
                # ID the atom in r_moty
                r = m2r_isom[s]
                # add the index offset
                r += parent.atoms.n + (count_xrms - 1) * xrm.atoms.n
                # push bond to array
                push!(bonds, (nᵢ, r))
            end
        end
    end
    # new fragment bonds
    # calculate indices in new xtal
    offset = (count_xrms - 1) * xrm.atoms.n + parent.atoms.n
    for e in edges(xrm.bonds) # loop over fragment edges
        push!(bonds, (offset + src(e), offset + dst(e)))
    end
end


# generates data for effecting a series of replacements
function build_replacement_data(configs::Array{Tuple{Int,Int}}, search::Search,
        parent::Crystal, s_moty::Crystal, r_moty::Crystal, m2r_isom::Array{Int},
        mask::Crystal)::Tuple{Array{Crystal},Array{Int},Array{Tuple{Int,Int}}}
    xrms = Crystal[]
    del_atoms = Int[]
    bonds = Tuple{Int,Int}[] # tuple (i,j) encodes a parent[i] -> xrms[k][j] bond
    # parent bonds
    for e in edges(parent.bonds) # loop over parent structure bonds
        push!(bonds, (src(e), dst(e))) # preserve them
    end
    # generate transformed replace moiety (xrm), ID which atoms to delete,
    # and accumulate list of bonds for each replacement configuration
    s′_in_r = mask ∈ r_moty
    for config in configs
        # find isomorphism
        s2p_isom = search.results[config[1]].isomorphism[config[2]]
        # find parent subset
        parent_subset = deepcopy(parent[s2p_isom])
        # adjust coordinates for periodic boundaries
        adjust_for_pb!(parent_subset)
        # record the center of xtal_subset so we can translate back later
        parent_subset_center = geometric_center(parent_subset)
        # shift to align centers at origin
        center_on_self!.([parent_subset, s_moty])
        # orthog. Procrustes for s_moty-to-parent and mask-to-replacement alignments
        rot_s2p = s2p_op(s_moty, parent_subset)
        xrm = nothing
        m2r_isom = nothing
        if nb_isomorphisms(s′_in_r) ≠ 0
            # choose best r2m by evaluating MAE for all possibilities
            rot_r2m_err = Inf
            for m2r_isom′ ∈ [s′_in_r.results[i].isomorphism[1] for i ∈ 1:nb_locations(s′_in_r)]
                # shift all r_moty nodes according to center of isomorphic subset
                r_moty′ = deepcopy(r_moty)
                r_moty′.atoms.coords.xf .-= geometric_center(r_moty[m2r_isom′])
                rot_r2m = r2m_op(r_moty, s_moty, m2r_isom′, mask.atoms)
                # transform r_moty by rot_r2m, rot_s2p, and xtal_subset_center, align
                # to parent (this is now a crystal to add)
                xrm = xform_r_moty(r_moty′, rot_r2m, rot_s2p, parent_subset_center, parent)
                rot_r2m_err′ = rmsd(xrm.atoms.coords.xf[:, m2r_isom′], mask.atoms.coords.xf[:, :])
                if rot_r2m_err′ < rot_r2m_err
                    m2r_isom = m2r_isom′
                    rot_r2m_err = rot_r2m_err′
                end
            end
            push!(xrms, xrm)
        end
        # push obsolete atoms to array
        for x in s2p_isom
            push!(del_atoms, x) # this can create duplicates; remove them later
        end
        # clean up del_atoms
        del_atoms = unique(del_atoms)
        # accumulate bonds
        accumulate_bonds!(bonds, s2p_isom, parent, m2r_isom, xrm, length(xrms))
    end
    return xrms, del_atoms, bonds
end


## Search function (exposed)
@doc raw"""
    substructure_search(s_moty, xtal; exact=false)

Searches for a substructure within a `Crystal` and returns a `Search` struct
containing all identified subgraph isomorphisms.  Matches are made on the basis
of atomic species and chemical bonding networks, including bonds across unit cell
periodic boundaries.  The search moiety may optionally contain markup for
designating atoms to replace with other moieties.

# Arguments
- `s_moty::Crystal` the search moiety
- `xtal::Crystal` the parent structure
- `exact::Bool=false` if true, disables substructure searching and performs only exact matching
"""
function substructure_search(s_moty::Crystal, xtal::Crystal; exact::Bool=false)::Search
    # Make a copy w/o R tags for searching
    moty = deepcopy(s_moty)
    untag_r_group!(moty)
    # Get array of configuration arrays
    configs = Ullmann.find_subgraph_isomorphisms(moty.bonds,
        moty.atoms.species, xtal.bonds, xtal.atoms.species, exact)
    df = DataFrame(p_subset=[sort(c) for c in configs], isomorphism=configs)
    locs = Int[]
    isoms = Array{Int}[]
    for (i, loc) in enumerate(groupby(df, :p_subset))
        for isom in loc.isomorphism
            push!(locs, i)
            push!(isoms, isom)
        end
    end
    results = groupby(DataFrame(location=locs, isomorphism=isoms), :location)
    return Search(Query(xtal, s_moty), results)
end


## Internal method for performing substructure replacements
function substructure_replace(s_moty::Crystal, r_moty::Crystal, parent::Crystal,
        search::Search, configs::Array{Tuple{Int,Int}},
        new_xtal_name::String)::Crystal
    # configs must all be unique
    @assert length(configs) == length(unique(configs)) "configs must be unique"
    # mutation guard
    s_moty, r_moty = deepcopy.([s_moty, r_moty])
    # if there are no replacements to be made, just return the parent
    if nb_isomorphisms(search) == 0
        @warn "No replacements to be made."
        return parent
    end
    # determine s_mask (which atoms from s_moty are NOT in r_moty?)
    mask = s_moty[idx_filter(s_moty, r_group_indices(s_moty))]
    # get isomrphism between s_moty/mask and r_moty
    s′_in_r = mask ∈ r_moty
    if nb_isomorphisms(s′_in_r) ≠ 0
        m2r_isom = s′_in_r.results[1].isomorphism[1]
        # shift all r_moty nodes according to center of isomorphic subset
        r_moty.atoms.coords.xf .-= geometric_center(r_moty[m2r_isom])
    else
        m2r_isom = Int[]
    end
    # loop over configs to build replacement data
    xrms, del_atoms, bonds = build_replacement_data(configs, search, parent, s_moty,
        r_moty, m2r_isom, mask)
    # append temporary crystals to parent
    atoms = xrms == Crystal[] ? parent.atoms : parent.atoms + sum([xrm.atoms for xrm ∈ xrms if xrm.atoms.n > 0])
    xtal = Crystal(new_xtal_name, parent.box, atoms, Charges{Frac}(0))
    # create bonds from tuple array
    for (i, j) ∈ bonds
        add_edge!(xtal.bonds, i, j)
    end
    # correct for periodic boundaries
    wrap!(xtal)
    # slice to final atoms/bonds
    new_xtal = xtal[[x for x ∈ 1:xtal.atoms.n if !(x ∈ del_atoms)]]
    # calculate bond attributes
    for bond ∈ edges(new_xtal.bonds)
        dist = distance(new_xtal.atoms, new_xtal.box, src(bond), dst(bond), true)
        cross_pb = dist == distance(new_xtal.atoms, new_xtal.box, src(bond), dst(bond), false)
        set_props!(new_xtal.bonds, bond, Dict(:distance => dist, :cross_boundary => cross_pb))
    end
    return new_xtal
end


## Find/replace function (exposed)
@doc raw"""
    find_replace(search, r_moty, nb_loc=2)

Inserts `r_moty` into a parent structure according to `search` and `kwargs`.
A valid replacement scheme must be selected by assigning one or more of the optional
`kwargs`.  Returns a new `Crystal` with the specified modifications (returns
`search.query.parent` if no replacements are made)

# Arguments
- `search::Search` the `Search` for a substructure moiety in the parent crystal
- `r_moty::Crystal` the moiety to use for replacement of the searched substructure
- `rand_all::Bool` set `true` to select random replacement at all matched locations
- `nb_loc::Int` assign a value to select random replacement at `nb_loc` random locations
- `loc::Array{Int}` assign value(s) to select specific locations for replacement.  If `ori` is not specified, replacement orientation is random.
- `ori::Array{Int}` assign value(s) when `loc` is assigned to specify exact configurations for replacement.
- `name::String` assign to give the generated `Crystal` a name ("new_xtal" by default)
"""
function find_replace(search::Search, r_moty::Crystal; rand_all::Bool=false,
        nb_loc::Int=0, loc::Array{Int}=Int[], ori::Array{Int}=Int[],
        name::String="new_xtal")::Crystal
    # handle input
    if rand_all # random replacement at each location
        nb_loc = nb_locations(search)
        loc = [1:nb_loc...]
        ori = [rand(1:nb_configs_at_loc(search)[i]) for i in loc]
    # random replacement at nb_loc random locations
    elseif nb_loc > 0 && ori == Int[] && loc == Int[]
        loc = sample([1:nb_locations(search)...], nb_loc, replace=false)
        ori = [rand(1:nb_configs_at_loc(search)[i]) for i in loc]
    elseif ori ≠ Int[] && loc ≠ Int[] # specific replacements
        @assert length(loc) == length(ori) "one orientation per location"
        nb_loc = length(ori)
    elseif loc ≠ Int[] # random replacement at specific locations
        nb_loc = length(loc)
        ori = [rand(1:nb_configs_at_loc(search)[i]) for i in loc]
    else
        @error "Invalid or missing replacement scheme."
    end
    # generate configuration tuples (location, orientation)
    configs = Tuple{Int,Int}[(loc[i], ori[i]) for i in 1:nb_loc]
    # process replacements
    return substructure_replace(search.query.s_moty, r_moty, search.query.parent,
        search, configs, name)
end
