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
						local res = api.sendMessage(k, pvText, 'html', keyboard)
						if res then count = count + 1
						else db:hdel('chat:' .. msg.chat.id .. ':ping', k)
						end
					end
					text = i18n('Pinging completed. successfully pinged <code>%d</code> people'):format(count)
					db:del('chat:' .. msg.chat.id .. ':ping:lock')
				end
			end
			api.sendMessage(chat_id, text, 'html', nil, msg.message_id)
		elseif blocks[1] == 'pingem' and u.is_mod(chat_id , msg.from.id) then
			local user_id, err = u.get_user_id(msg, blocks)
			if not user_id and err then
				api.sendMessage(chat_id, err, 'html', nil, msg.message_id)
			else
				local hash = 'chat:' .. chat_id .. ':ping'
				local name = db:hget(hash, user_id)
				if name then 
					text = 'They are in ping list already'
				else
					name = (msg.reply and msg.reply.from.first_name) or blocks[2]
					text = ('%s Successfully added to ping list'):format(u.getname_link(name, nil, user_id))
					db:hset(hash, user_id, name)
				end
				api.sendMessage(chat_id, text, 'html', nil, msg.message_id)
			end
		elseif blocks[1] == 'unpingem' and u.is_mod(chat_id , msg.from.id) then
			local user_id, err = u.get_user_id(msg, blocks)
			if not user_id and err then
				api.sendMessage(chat_id, err, 'html', nil, msg.message_id)
			else
				local hash = 'chat:' .. chat_id .. ':ping'
				local name = db:hget(hash, user_id)
				local text
				if not name then
					text = 'They are not in ping list already'
				else
					text = ('%s Successfully removed from ping list'):format(u.getname_link(name, nil, user_id))
					hash = 'chat:' .. chat_id .. ':ping'
					db:hdel(hash, user_id)
				end
				api.sendMessage(chat_id, text, 'html', nil, msg.message_id)	
			end
		elseif blocks[1] == 'clearpinglist' and u.is_allowed('hammer', chat_id, msg.from) then
			local text = 'Do you really want to clean pinglist for this group?'
			local keyboard =
			{
				inline_keyboard =
				{{{text = i18n('Yes'), callback_data = 'cleanpinglist:yes'}, {text = i18n('No'), callback_data = 'cleanpinglist:no'}}}
			}
			api.sendMessage(chat_id, text, 'html', keyboard, msg.message_id)
		end
	end
end

function plugin.onCallbackQuery(msg, blocks)
	if not u.is_allowed('hammer', msg.chat.id, msg.from) then
		api.answerCallbackQuery(msg.cb_id, i18n("You are not allowed to use this button")) return
	end
	if blocks[1] == 'cleanpinglist' then
		if blocks[2] == 'yes' then
			db:del('chat:' .. msg.chat.id .. ':ping')
			api.editMessageText(msg.chat.id, msg.message_id,
				i18n('Done. Ping list for this group is cleaقed by %s'):format(u.getname_final(msg.from)), 'html')
		else
			api.editMessageText(msg.chat.id, msg.message_id, i18n('_Action aborted_'), 'html')
		end
	end
end

plugin.triggers = {
	onTextMessage = {
		config.cmd..'(pingstatus)$',
		config.cmd..'(pingem)%s+(%S+)$',
		config.cmd..'(pingem)$',
		config.cmd..'(pingall)$',
		config.cmd..'(unpingem)%s+(%S+)$',
		config.cmd..'(unpingem)$',
		config.cmd..'(clearpinglist)$',
		'^/start (-?%d+)_(pingme)$',
		'^/start (-?%d+)_(pingme)$',
		'^/start (-?%d+)_(unpingme)$',

	},
	onCallbackQuery = {
		'^###cb:(cleanpinglist):(%w+)$',
	}
}

return plugin
