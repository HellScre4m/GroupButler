#!/usr/bin/env lua
package.path=package.path .. ';./lua/?.lua'

local api = require 'methods'
local clr = require 'term.colors'
local plugins = require 'plugins'
local u = require 'utilities'
local db = require 'database'
local chronos = require 'chronos'

local last_update, last_cron, current
----- statistical parallelism variables
local dop = db:hget('bot:parallelism', 'dop') or 2 -- Degree of parallelism
local tts = db:hget('bot:parallelism', 'tts') or 0.001 -- Mean time which it takes for main thread to find/allocate a worker thread
local samples = 128 -- Increasing this value makes statistics less prone to sudden spikes but also less flexible
local nol = 0 -- Number of lanes
----- End of statistical parallelism variables
local lanes = require 'lanes'.configure({nb_keepers = math.floor(dop + 1), verbose_errors = true, with_timers = false})
local linda = lanes.linda()
local lanesRepo = {}
local lastUpdates = {}
local laneIndex = 0

local function addLane()
	laneIndex = laneIndex + 1
	local lane = lanes(laneIndex)
	lanesRepo[laneIndex] = lane
	lastUpdates[laneIndex] = os.time()
	repeat linda:receive(0.001, 'dummy')
	until lane.status == 'waiting'
	print(clr.green..'New lane spawned...'..clr.reset)
	nol = nol + 1
	return lane, laneIndex
end

local function removeLane(lane, index)
	lanesRepo[index] = nil
	lastUpdates[index] = nil
	linda:send(nil, index, {code = 'cancel'})
	nol = nol - 1
	print(clr.red..'Lane removed...'..clr.reset)
end

local function init_lanes()
	local function laneFunction(index)
		local config = require 'config'
		for k,v in pairs(config.plugins) do
			if v == 'admin' then
				table.remove(config.plugins, k)
				break
			end
		end
		local handler = require 'main'
		handler.linda = linda
		local alive = true
		while alive do
			local _, update = linda:receive(nil, index)
			if update.code == 'cancel' then
				alive = false
			elseif update.code == 'init' then
				bot.init()
			else
				handler.parseMessageFunction(update.content)
				linda:send(nil, 'ready', index)
			end
		end
	end
	lanes = lanes.gen('*', laneFunction)
	addLane()
	linda:send(nil, 'ready', laneIndex)
end

init_lanes()
bot = {}

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

local main = require 'main'
main.linda = linda
bot.init()

local function maintenance()
	for i,j in pairs(lanesRepo) do
		if j.status == 'waiting' and os.time() - lastUpdates[i] > 300 then
			removeLane(j, i)
		elseif j.status == 'error' then
			_, err = j:join()
			print(err)
			removeLane(j, i)
		end
	end
	dop = ((samples - 1) * dop + nol) / samples
end
	
function processUpdate(update)
	if update.message then
		local msg = update.message
		if u.is_superadmin(msg.from.id) and msg.from.id == msg.chat.id then
		print('Admin command')
		-- Messages that super admin sends in PV should always be handled on the main thread.
			main.parseMessageFunction(update)
			return
		end
	end
	local container = {}
	container.code = 'update'
	container.content = update
	local begintime = chronos.nanotime()
	while true do
		local _, index = linda:receive(tonumber(tts), 'ready')
		local miss
		if index then
			local lane = lanesRepo[index]
			if lane and lane.status == 'waiting' then
				linda:send(nil, index, container)
				lastUpdates[index] = os.time()
				break
			else miss = true
			end
		end
		if not miss and nol < math.floor(dop * 1.5) then 
			_, index = addLane()
			linda:send(nil, index, container)
			break
		end
	end
	tts = math.floor(((samples - 1) * tts + chronos.nanotime() - begintime) * 1000 / samples)  / 1000
	maintenance()
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
		db:hmset('bot:parallelism', 'dop', dop, 'tts', tts)
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
