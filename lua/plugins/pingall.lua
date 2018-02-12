local config = require 'config'
local u = require 'utilities'
local api = require 'methods'
local db = require 'database'
local locale = require 'languages'
local i18n = locale.translate

local plugin = {}

local function doKeyboard_pingstatus(user_id, chat_id)
	local keyboard = {}
	keyboard.inline_keyboard = {{{text = i18n("Register"),  url = u.deeplink_constructor(chat_id, 'pingme')}, 
	{text = i18n("Unregister"),  url = u.deeplink_constructor(chat_id, 'unpingme')}}}

	return keyboard
end

local function doKeyboard_unpingme(user_id, chat_id)
	local keyboard = {}
	keyboard.inline_keyboard = {{{text = i18n("Cancel"),  url = u.deeplink_constructor(chat_id, 'unpingme')}}}

	return keyboard
end

local function doKeyboard_pingme(user_id, chat_id)
	local keyboard = {}
	keyboard.inline_keyboard = {{{text = i18n("Register"),  url = u.deeplink_constructor(chat_id, 'pingme')}}}

	return keyboard
end

function plugin.onTextMessage(msg, blocks)
	if msg.chat.type == 'private' then
		if blocks[2] == 'pingme' then
			local user_id = msg.from.id
			local chat_id = blocks[1]
			local hash = 'chat:' .. chat_id .. ':ping'
			local chat_title = db:get('chat:' .. chat_id .. ':title') or chat_id
			local name = msg.from.first_name
			db:hset(hash, user_id, name)
			local text = i18n("You've successfully registered for pingall in %s")
			local link = db:hget('chat:' .. chat_id .. ':links', 'link')
			local append
			if link then
				append = ('<a href="%s">%s</a>'):format(link, chat_title)
			else append = chat_title
			end
			text = text:format(append)
			local keyboard = doKeyboard_unpingme(user_id, chat_id)
			api.sendMessage(user_id, text, 'html', keyboard)
		elseif blocks[2] == 'unpingme' then
			local user_id = msg.from.id
			local chat_id = blocks[1]
			local hash = 'chat:' .. chat_id .. ':ping'
			local chat_title = db:get('chat:' .. chat_id .. ':title') or chat_id
			db:hdel(hash, user_id)
			local text = i18n("You've successfully unregistered from pingall in %s")
			local link = db:hget('chat:' .. chat_id .. ':links', 'link')
			local append
			if link then
				append = ('<a href="%s">%s</a>'):format(link, chat_title)
			else append = chat_title
			end
			text = text:format(append)
			local keyboard = doKeyboard_pingme(user_id, chat_id)
			api.sendMessage(user_id, text, 'html', keyboard)
		end
	elseif msg.chat.type ~= 'channel' then
		local chat_id = msg.chat.id
		if blocks[1] == 'pingstatus' then
			local link = db:hget('chat:' .. msg.chat.id .. ':links', 'link')
			local text, keyboard
			if not link then
				text = i18n('Sorry, link for this group is not set. Ask admins to set it via <code>/setlink</code>')
			else
				text = i18n('What do you want to do?')
				keyboard = doKeyboard_pingstatus(msg.from.id, msg.chat.id)
				db:set('chat:' .. msg.chat.id .. ':title', msg.chat.title)
			end
			api.sendMessage(chat_id, text, 'html', keyboard, msg.message_id)
		elseif blocks[1] == 'pingall' then
			local link = db:hget('chat:' .. msg.chat.id .. ':links', 'link')
			if not link then
				text = i18n('Sorry, link for this group is not set. Ask admins to set it via <code>/setlink</code>')
				api.sendMessage(chat_id, text, 'html', nil, msg.message_id)
				return
			end
			local lock = db:get('chat:' .. msg.chat.id .. ':ping:lock')
			local text
			if lock then
				text = i18n('Sorry but a <code>/pingall</code> is already in progress for this group')
			else
				local list = db:hgetall('chat:' .. msg.chat.id .. ':ping')
				if not list then
					text = i18n('No one is registered for ping in this group yet! Try <code>/pingme</code> to register')
				else
					lock = db:setex('chat:' .. msg.chat.id .. ':ping:lock', 3600, 1)
					text = i18n('Pinging started. Ack will be sent after completion')
					api.sendMessage(chat_id, text, 'html', nil, msg.message_id)
					count = 0
					link = ('<a href="%s">%s</a>'):format(link, msg.chat.title)
					local keyboard = doKeyboard_unpingme(k, msg.chat.id)
					for k,v in pairs(list) do
						local mention = ('<a href="tg://user?id=%s">%s</a>'):format(k, v)
						local pvText = i18n("Dear %s You've been pinged in group: %s"):format(mention, link)
						local res = api.sendMessage(k, pvText, 'html', keyboard, nil, true)
						if res then count = count + 1 end
					end
					text = i18n('Pinging completed. successfully pinged <code>%d</code> people'):format(count)
					db:del('chat:' .. msg.chat.id .. ':ping:lock')
				end
			end
			api.sendMessage(chat_id, text, 'html', nil, msg.message_id)
		end
		
	
	
	
	end

end

function plugin.onCallbackQuery(msg, blocks)

end

plugin.triggers = {
	onTextMessage = {
		config.cmd..'(pingstatus)$',
		config.cmd..'(pingem)%s+(%S+)$',
		config.cmd..'(pingall)$',
		config.cmd..'(unpingem)%s+(%S+)$',
		'^/start (-?%d+)_(pingme)$',
		'^/start (-?%d+)_(unpingme)$',

	},
}

return plugin
