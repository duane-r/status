-- Status init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2017
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)

status_mod = {}
status_mod.version = "1.0"
status_mod.path = minetest.get_modpath(minetest.get_current_modname())
status_mod.world = minetest.get_worldpath()
status_mod.registered_status = {}

local status_delay = 3
local last_status_check = 0


local inp = io.open(status_mod.world..'/status_data.txt','r')
if inp then
	local d = inp:read('*a')
	status_mod.db = minetest.deserialize(d)
	inp:close()
end
if not status_mod.db then
	status_mod.db = {}
end
for _, i in pairs({'status'}) do
	if not status_mod.db[i] then
		status_mod.db[i] = {}
	end
end


function status_mod.register_status(def)
	if not (def and status_mod.registered_status and type(def) == 'table') then
		return
	end

	status_mod.registered_status[def.name] = {
		remove = def.remove,
		start = def.start,
		during = def.during,
		terminate = def.terminate,
    remain_after_death = def.remain_after_death,
	}
end

function status_mod.set_status(player_name, status, time, param)
	if not (player_name and type(player_name) == 'string' and status and type(status) == 'string') and status_mod.db and status_mod.db.status and status_mod.db.status[player_name] then
		return
	end

	local player = minetest.get_player_by_name(player_name)
	local def = status_mod.registered_status[status]
	if not (def and player) then
		return
	end

	if not param then
		param = {}
	end

	if time then
		param.remove = (minetest.get_gametime() or 0) + time
	end

	status_mod.db.status[player_name][status] = param
	if def.start then
		def.start(player)
	end
end

function status_mod.remove_status(player_name, status)
	if not (player_name and type(player_name) == 'string' and status and type(status) == 'string') and status_mod.db and status_mod.db.status and status_mod.db.status[player_name] then
		return
	end

	local player = minetest.get_player_by_name(player_name)
	local def = status_mod.registered_status[status]
	if player and def then
		if def.terminate then
			status_mod.db.status[player_name][status] = def.terminate(player)
		else
			status_mod.db.status[player_name][status] = nil
		end
	end
end


-- Attempt to save data at shutdown (as well as periodically).
minetest.register_on_shutdown(function()
	local out = io.open(status_mod.world..'/status_data.txt','w')	
	if out then
		out:write(minetest.serialize(status_mod.db))
		out:close()
	end
end)


minetest.register_on_dieplayer(function(player)
	if status_mod.db.status and not player then
		return
	end

	local player_name = player:get_player_name()
	if not (player_name and type(player_name) == 'string' and player_name ~= '') then
		return
	end

	if status_mod.db.status[player_name] then
		for status in pairs(status_mod.db.status[player_name]) do
			local def = status_mod.registered_status[status]
			if not def.remain_after_death then
				status_mod.remove_status(player_name, status)
			end
		end
	end
end)


minetest.register_on_joinplayer(function(player)
	if not (player and status_mod.db.status) then
		return
	end

	local player_name = player:get_player_name()

	if not (player_name and type(player_name) == 'string' and player_name ~= '') then
		return
	end

	if not status_mod.db.status[player_name] then
		status_mod.db.status[player_name] = {}
	end
end)


minetest.register_globalstep(function(dtime)
	if not (dtime and type(dtime) == 'number') then
		return
	end

	if not (status_mod.db.status and status_mod.registered_status) then
		return
	end

	local time = minetest.get_gametime()
	if not (time and type(time) == 'number') then
		return
	end

	if last_status_check and time - last_status_check < status_delay then
		return
	end

	local players = minetest.get_connected_players()

	for i = 1, #players do
		local player = players[i]
		local pos = player:getpos()
		pos = vector.round(pos)
		local player_name = player:get_player_name()

		-- Execute only after an interval.
		if last_status_check and time - last_status_check >= status_delay then
			-- environmental damage
			local minp = vector.subtract(pos, 0.5)
			local maxp = vector.add(pos, 0.5)

			-- Remove status effects.
			local status = status_mod.db.status[player_name]
			for status_name, status_param in pairs(status) do
				local def = status_mod.registered_status[status_name]
				if not def then
					print('Status: Error - unregistered status ' .. status_name)
					break
				end

				local remove
				if type(status_param.remove) == 'number' then
					if status_param.remove < time then
						remove = true
					end
				elseif def.remove then
					remove = def.remove(player)
				else
					print('Status: Error in status remove for ' .. status_name)
				end

				if remove then
					status_mod.remove_status(player_name, status_name)
				elseif def.during then
					def.during(player)
				end
			end

			if status_mod.db.status[player_name]['breathe'] then
				player:set_breath(11)
			end
    end
	end

	-- Execute only after an interval.
	if last_status_check and time - last_status_check < status_delay then
		return
	end

	local out = io.open(status_mod.world..'/status_mod_data.txt','w')	
	if out then
		out:write(minetest.serialize(status_mod.db))
		out:close()
	end

	last_status_check = minetest.get_gametime()
	if not (last_status_check and type(last_status_check) == 'number') then
		last_status_check = 0
	end
end)
