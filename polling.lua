#!/usr/bin/env lua
package.path=package.path .. ';./lua/?.lua'

local api = require 'methods'
local clr = require 'term.colors'
local plugins = require 'plugins'
local u = require 'utilities'

local last_update, last_cron, current

local lanes = require 'lanes'.configure({track_lanes = true})
local linda = lanes.linda()
local lanesRepo = {}
local lastUpdates = {}
local laneIndex = 0

local function addLane()
	laneIndex = laneIndex + 1
	local lane = lanes(laneIndex)
	lanesRepo[laneIndex] = lane
	lastUpdates[laneIndex] = os.time()
	repeat linda:receive(0.001,'dummmy')
	until lane.status == 'waiting'
	print(clr.green..'New lane spawned...'..clr.reset)
	return lane
end

local function removeLane(lane, index)
	lanesRepo[index] = nil
	lastUpdates[index] = nil
	local update = {code = 'cancel'}
	linda:send(nil, index, update)
	print(clr.red..'Lane removed...'..clr.reset)
end

local function init_lanes()
	local opt_table = {}
	opt_table.globals = {bot}
	local function laneFunction(index)
		local config = require 'config'
		config.plugins['admin'] = nil
		local handler = require 'main'
		handler.linda = linda
		local alive = true
		while alive do
			local _, update = linda:receive(nil, index)
			if update.code == 'cancel' then
				alive = false
			elseif update.code == 'init' then
				bot.init()
			else handler.parseMessageFunction(update.content)
			end
		end
	end
	lanes = lanes.gen('*', opt_table, laneFunction)
	addLane()
end

init_lanes()
local main = require 'main'

function bot.init(on_reload) -- The function run when the bot is started or reloaded
	if on_reload then
		package.loaded.config = nil
		package.loaded.languages = nil
		package.loaded.utilities = nil
		package.loaded.methods = nil
		package.loaded.plugins = nil
		require 'config'
		require 'languages'
		u = require 'utilities'
		api = require 'methods'
		plugins = require 'plugins'
		for k,v in pairs(lanesRepo) do
			if v.status == 'waiting' and os.time() - lastUpdates[k] > 300 then
				removeLane(v, k) -- if it needs to be removed then there is no need to re init
			else
				linda:send(nil, k, {code = 'init'}) -- Notify worker thread to init 
			end
		end
	end

	print('\n'..clr.blue..'BOT RUNNING:'..clr.reset,
		clr.red..'[@'..bot.username .. '] [' .. bot.first_name ..'] ['..bot.id..']'..clr.reset..'\n')

	last_update = last_update or -2 -- skip pending updates
	last_cron = last_cron or os.time() -- the time of the last cron job

	if on_reload then
		return #plugins
	else
		api.sendAdmin('*Bot started!*\n_'..os.date('On %A, %d %B %Y\nAt %X')..'_\n'..#plugins..' plugins loaded', true)
		bot.start_timestamp = os.time()
		current = {h = 0}
		bot.last = {h = 0}
	end
end

main.linda = linda
bot.init()

function processUpdate(update)
	if update.message then
		local msg = update.message
		if u.is_superadmin(msg.from.id) and msg.from.id == msg.chat.id then
		-- Messages that super admin sends in PV should always be handled on the main thread.
			main.parseMessageFunction(update)
			return
		end
	end
	local container = {}
	container.code = 'update'
	container.content = update
	local tries = 0
	while true do
		local count = 0
		for k,v in pairs(lanesRepo) do
			count = count + 1
			if v.status == 'waiting' then
				linda:send (nil, k, container)
				lastUpdates[k] = os.time()
				for i,j in pairs(lanesRepo) do
					if j.status == 'waiting' and os.time() - lastUpdates[i] > 300 then
						removeLane(j, i)
					end
				end
				return
			elseif v.status == 'error' then
				_, err = v:join()
				print(err)
				removeLane(k, v)
			end
		end
		tries = tries + 1
		linda:receive(0.01, 'dummy')
		if tries == 32 - count then
			if count < 32 then addLane() end
			tries = 0
		end
	end
end

api.firstUpdate()
while true do -- Start a loop while the bot should be running.
	local res = api.getUpdates(last_update+1) -- Get the latest updates
	if res then
		-- clocktime_last_update = os.clock()
		for i=1, #res.result do -- Go through every new message.
			last_update = res.result[i].update_id
			--print(last_update)
			current.h = current.h + 1
			processUpdate(res.result[i])
		end
	else
		print('Connection error')
	end
	if last_cron ~= os.date('%H') then -- Run cron jobs every hour.
		last_cron = os.date('%H')
		-- last.h = current.h
		current.h = 0
		print(clr.yellow..'Cron...'..clr.reset)
		for i=1, #plugins do
			if plugins[i].cron then -- Call each plugin's cron function, if it has one.
				local res2, err = pcall(plugins[i].cron)
				if not res2 then
					api.sendLog('An #error occurred (cron).\n'..err)
					return
				end
			end
		end
	end
end
