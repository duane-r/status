-- Status init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)

status_mod = {}
local mod = status_mod
local mod_name = 'status'
mod.version = "20190530"
mod.path = minetest.get_modpath(minetest.get_current_modname())
mod.world = minetest.get_worldpath()
mod.registered_status = {}

local status_delay = 3
local last_status_check = 0


local sdata = minetest.get_mod_storage()


function mod.register_status(def)
	if type(def) ~= 'table' then
		print(mod_name..': parameter error in register_status')
		return
	end

	mod.registered_status[def.name] = {
		remove = def.remove,
		start = def.start,
		during = def.during,
		terminate = def.terminate,
		remain_after_death = def.remain_after_death,
	}
end

function mod.set_status(player_name, status, time, param)
	if type(player_name) ~= 'string'
	or type(status) ~= 'string' then
		print(mod_name..': parameter error in set_status')
		return
	end

	local player = minetest.get_player_by_name(player_name)
	local def = mod.registered_status[status]
	if not (def and player) then
		print(mod_name..': missing status definition in set_status')
		return
	end

	if not param then
		param = {}
	end

	if time then
		param.remove = (minetest.get_gametime() or 0) + time
	end

	sdata:set_string(player_name..status, minetest.serialize(param))
	if def.start then
		def.start(player)
	end
end

function mod.remove_status(player_name, status)
	if type(player_name) ~= 'string' 
	or type(status) ~= 'string' then
		print(mod_name..': parameter error in remove_status')
		return
	end

	local player = minetest.get_player_by_name(player_name)
	local def = mod.registered_status[status]
	if player and def then
		if def.terminate then
			local res = def.terminate(player)
			if res then
				sdata:set_string(player_name..status, minetest.serialize(res))
			else
				sdata:set_string(player_name..status, '')
			end
		else
			sdata:set_string(player_name..status, '')
		end
	end
end


function mod.has_status(player_name, status)
	if type(player_name) ~= 'string' 
	or type(status) ~= 'string' then
		print(mod_name..': parameter error in has_status')
		return
	end

	if sdata:contains(player_name..status) then
		return true
	end
end


function mod.get_status(player_name, status)
	if type(player_name) ~= 'string' 
	or type(status) ~= 'string' then
		print(mod_name..': parameter error in get_status')
		return
	end

	if sdata:contains(player_name..status) then
		local status_param = minetest.deserialize(sdata:get_string(player_name..status))
		return status_param
	end
end


minetest.register_on_dieplayer(function(player)
	if not player then
		return
	end

	local player_name = player:get_player_name()
	if type(player_name) ~= 'string' or player_name == '' then
		return
	end

	for status, def in pairs(mod.registered_status) do
		if sdata:contains(player_name..status)
		and not def.remain_after_death then
			mod.remove_status(player_name, status)
		end
	end
end)


minetest.register_globalstep(function(dtime)
	local time = minetest.get_gametime()
	if type(time) ~= 'number' then
		return
	end

	if time - last_status_check < status_delay then
		return
	end

	local players = minetest.get_connected_players()

	for i = 1, #players do
		local player = players[i]
		local pos = player:getpos()
		pos = vector.round(pos)
		local player_name = player:get_player_name()

		-- environmental damage
		local minp = vector.subtract(pos, 0.5)
		local maxp = vector.add(pos, 0.5)

		-- Remove status effects.
		for status, def in pairs(mod.registered_status) do
			if sdata:contains(player_name..status) then
				local remove
				local status_param = minetest.deserialize(sdata:get_string(player_name..status))
				if type(status_param) == 'table' then
					if type(status_param.remove) == 'number' then
						remove = (status_param.remove < time)
					elseif def.remove then
						remove = def.remove(player)
					end
				end

				if remove then
					mod.remove_status(player_name, status)
				elseif def.during then
					def.during(player)
				end
			end
		end

		if sdata:contains(player_name..'breathe') then
			player:set_breath(11)
		end
	end

	last_status_check = minetest.get_gametime()
end)
