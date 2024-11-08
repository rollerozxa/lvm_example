-- Set the 3D noise parameters for the terrain.
local np_terrain = {
	offset = 0,
	scale = 1,
	spread = {x = 384, y = 192, z = 384},
	seed = 5900033,
	octaves = 5,
	persist = 0.63,
	lacunarity = 2.0,
	--flags = ""
}

-- Set singlenode mapgen (air nodes only).
-- Disable the engine lighting calculation since that will be done for a
-- mapchunk of air nodes and will be incorrect after we place nodes.
core.set_mapgen_setting("mg_name", "singlenode", true)
core.set_mapgen_setting("mg_flags", "nolight", true)

-- Get the content IDs for the nodes used.
local c_stone, c_water
core.register_on_mods_loaded(function()
	c_stone = core.get_content_id("mapgen_stone")
	c_water = core.get_content_id("mapgen_water_source")
end)

-- Initialize noise object to nil. It will be created once only during the
-- generation of the first mapchunk, to minimise memory use.
local nobj_terrain = nil

-- Localise noise buffer table outside the loop, to be re-used for all
-- mapchunks, therefore minimising memory use.
local nvals_terrain = {}

-- Localise data buffer table outside the loop, to be re-used for all
-- mapchunks, therefore minimising memory use.
local data = {}

-- Whether the 'biomegen' mod exists.
local use_biomegen = core.get_modpath('biomegen')

-- On generated function.

-- 'minp' and 'maxp' are the minimum and maximum positions of the mapchunk that
-- define the 3D volume.
core.register_on_generated(function(minp, maxp, seed)
	-- Start time of mapchunk generation.
	local t0 = os.clock()

	-- Noise stuff.

	-- Side length of mapchunk.
	local sidelen = maxp.x - minp.x + 1
	-- Required dimensions of the 3D noise perlin map.
	local permapdims3d = {x = sidelen, y = sidelen, z = sidelen}
	-- Create the perlin map noise object once only, during the generation of
	-- the first mapchunk when 'nobj_terrain' is 'nil'.
	nobj_terrain = nobj_terrain or
		core.get_perlin_map(np_terrain, permapdims3d)
	-- Create a flat array of noise values from the perlin map, with the
	-- minimum point being 'minp'.
	-- Set the buffer parameter to use and reuse 'nvals_terrain' for this.
	nobj_terrain:get_3d_map_flat(minp, nvals_terrain)

	-- Voxelmanip stuff.

	-- Load the voxelmanip with the result of engine mapgen. Since 'singlenode'
	-- mapgen is used this will be a mapchunk of air nodes.
	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	-- 'area' is used later to get the voxelmanip indexes for positions.
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	-- Get the content ID data from the voxelmanip in the form of a flat array.
	-- Set the buffer parameter to use and reuse 'data' for this.
	vm:get_data(data)

	-- Generation loop.

	-- Noise index for the flat array of noise values.
	local ni = 1
	-- Process the content IDs in 'data'.
	-- The most useful order is a ZYX loop because:
	-- 1. This matches the order of the 3D noise flat array.
	-- 2. This allows a simple +1 incrementing of the voxelmanip index along x
	-- rows.
	for z = minp.z, maxp.z do
	for y = minp.y, maxp.y do
		-- Voxelmanip index for the flat array of content IDs.
		-- Initialise to first node in this x row.
		local vi = area:index(minp.x, y, z)
		for x = minp.x, maxp.x do
			-- Consider a 'solidness' value for each node,
			-- let's call it 'density', where
			-- density = density noise + density gradient.
			local density_noise = nvals_terrain[ni]
			-- Density gradient is a value that is 0 at water level (y = 1)
			-- and falls in value with increasing y. This is necessary to
			-- create a 'world surface' with only solid nodes deep underground
			-- and only air high above water level.
			-- Here '128' determines the typical maximum height of the terrain.
			local density_gradient = (1 - y) / 128
			-- Place solid nodes when 'density' > 0.
			if density_noise + density_gradient > 0 then
				data[vi] = c_stone
			-- Otherwise if at or below water level place water.
			elseif y <= 1 then
				data[vi] = c_water
			end

			-- Increment noise index.
			ni = ni + 1
			-- Increment voxelmanip index along x row.
			-- The voxelmanip index increases by 1 when
			-- moving by 1 node in the +x direction.
			vi = vi + 1
		end
	end
	end

	if use_biomegen then
		-- Generate biomes, decorations, ores and dust using biomegen.
		-- It will also call :set_data() for us.
		biomegen.generate_all(data, area, vm, minp, maxp, seed)
	else
		-- After processing, write content ID data back to the voxelmanip.
		vm:set_data(data)
	end

	-- Calculate lighting for what has been created.
	vm:calc_lighting()
	-- Write what has been created to the world.
	vm:write_to_map()
	-- Liquid nodes were placed so set them flowing.
	vm:update_liquids()

	-- Print generation time of this mapchunk.
	local chugent = math.ceil((os.clock() - t0) * 1000)
	print("[lvm_example] Mapchunk generation time " .. chugent .. " ms")
end)
