local config = require 'config'
local u = require 'utilities'
local api = require 'methods'
local db = require 'database'
local locale = require 'languages'
local i18n = locale.translate

local plugin = {}

local permissions = {
	can_change_info = i18n("can't change the chat title/description/icon"),
	can_send_messages = i18n("can't send messages"),
	can_delete_messages = i18n("can't delete messages"),
	can_invite_users = i18n("can't invite users/generate a link"),
	can_restrict_members = i18n("can't restrict members"),
	can_pin_messages = i18n("can't pin messages"),
	can_promote_members = i18n("can't promote new admins"),
	can_send_media_messages = i18n("can't send photos/videos/documents/audios/voice messages/video messages"),
	can_send_other_messages = i18n("can't send stickers/GIFs/games/use inline bots"),
	can_add_web_page_previews = i18n("can't show link previews")
}

local function do_keyboard_cache(chat_id)
	local keyboard = {inline_keyboard = {{{text = i18n("🔄️ Refresh cache"), callback_data = 'recache:'..chat_id}}}}
	return keyboard
end

local function get_time_remaining(seconds)
	local final = ''
	local hours = math.floor(seconds/3600)
	seconds = seconds - (hours*60*60)
	local min = math.floor(seconds/60)
	seconds = seconds - (min*60)

	if hours and hours > 0 then
		final = final..hours..'h '
	end
	if min and min > 0 then
		final = final..min..'m '
	end
	if seconds and seconds > 0 then
		final = final..seconds..'s'
	end

	return final
end

local function do_keyboard_userinfo(user_id)
	local keyboard = {
		inline_keyboard = {
			
			{
				{text = i18n("Remove warn"), callback_data = 'userbutton:removewarn:'..user_id},
				{text = i18n("Remove warnings"), callback_data = 'userbutton:remwarns:'..user_id},
				{text = i18n("Warn"), callback_data = 'userbutton:warn:'..user_id},
			},
			{
				{text = i18n("Kick"), callback_data = 'userbutton:kick:'..user_id},
				{text = i18n("Ban"), callback_data = 'userbutton:ban:'..user_id},
				{text = i18n("Unban"), callback_data = 'userbutton:unban:'..user_id},
			}
		
	}}

	return keyboard
end

local function get_userinfo(user_id, chat_id)
	local text = i18n([[<b>User ID</b>: %s
<b>Warnings</b>: <code>%d</code>
<b>Media warnings</b>: <code>%d</code>
<b>Spam warnings</b>: <code>%d</code>
]])
	local warns = (db:hget('chat:'..chat_id..':warns', user_id)) or 0
	local media_warns = (db:hget('chat:'..chat_id..':mediawarn', user_id)) or 0
	local spam_warns = (db:hget('chat:'..chat_id..':spamwarns', user_id)) or 0
	return text:format(('<code>%s</code>'):format(user_id), warns, media_warns, spam_warns)
end

function plugin.onTextMessage(msg, blocks)
	if blocks[1] == 'id' then --just for debug
		if msg.chat.id < 0 and msg.from.admin then
			api.sendMessage(msg.chat.id, string.format('`%d`', msg.chat.id), true)
			return
		end
	end

	if msg.chat.type == 'private' then return end

	if blocks[1] == 'adminlist' then
		local adminlist = u.getAdminlist(msg.chat.id)
		local res
		if not msg.from.admin then
			res = api.sendMessage(msg.from.id, adminlist, 'html')
		end
		if not res then
			api.sendReply(msg, adminlist, 'html')
		end
	elseif blocks[1] == 'status' then
		if msg.from.admin then
			if not blocks[2] and not msg.reply then return end
			local user_id, error_tr_id = u.get_user_id(msg, blocks)
			if not user_id then
				api.sendReply(msg, i18n(error_tr_id), true)
			else
				local res = api.getChatMember(msg.chat.id, user_id)

				if not res then
					api.sendReply(msg, i18n("That user has nothing to do with this chat"))
					return
				end
				local status = res.result.status
				local name = u.getname_final(res.result.user)
				local statuses = {
					kicked = i18n("%s is banned from this group"),
					left = i18n("%s left the group or has been kicked and unbanned"),
					administrator = i18n("%s is an admin"),
					creator = i18n("%s is the group creator"),
					unknown = i18n("%s has nothing to do with this chat"),
					member = i18n("%s is a chat member"),
					restricted = i18n("%s is a restricted")
				}
				local denied_permissions = {}
				for permission, str in pairs(permissions) do
					if res.result[permission] ~= nil and res.result[permission] == false then
						table.insert(denied_permissions, str)
					end
				end

				local text = statuses[status]:format(name)
				if next(denied_permissions) then
					text = text..i18n('\nRestrictions: <i>%s</i>'):format(table.concat(denied_permissions, ', '))
				end

				api.sendReply(msg, text, 'html')
			end
		end
	elseif blocks[1] == 'user' then
		if not msg.from.admin then return end
		local user_id, error_text = u.get_user_id(msg, blocks)
		local keyboard, text
		if user_id then
			keyboard = do_keyboard_userinfo(user_id)
			text = get_userinfo(user_id, msg.chat.id)
		else text = error_text
		end
		api.sendMessage(msg.chat.id, text, 'html', keyboard, msg.message_id)
	elseif blocks[1] == 'me' then
		local user_id = msg.from.id
		local text = get_userinfo(user_id, msg.chat.id)
		local res = api.sendMessage(msg.from.id, text, 'html')
		if not res then
			api.sendMessage(msg.chat.id, text, 'html', nil, msg.message_id)
		end
	elseif blocks[1] == 'cache' then
		if not msg.from.admin then return end
		local hash = 'cache:chat:'..msg.chat.id..':admins'
		local seconds = db:ttl(hash)
		local cached_admins = db:scard(hash)
		local text = i18n("📌 Status: `CACHED`\n⌛ ️Remaining: `%s`\n👥 Admins cached: `%d`")
			:format(get_time_remaining(tonumber(seconds)), cached_admins)
		local keyboard = do_keyboard_cache(msg.chat.id)
		api.sendMessage(msg.chat.id, text, true, keyboard)
	elseif blocks[1] == 'msglink' then
		if not msg.reply or not msg.chat.username then return end

		local text = string.format('[%s](https://telegram.me/%s/%d)',
			i18n("Message N° %d"):format(msg.reply.message_id), msg.chat.username, msg.reply.message_id)
		if msg.from.admin or not u.is_silentmode_on(msg.chat.id) then
			api.sendReply(msg.reply, text, true)
		else
			api.sendMessage(msg.from.id, text, true)
		end
	elseif blocks[1] == 'leave' then
		if msg.from.admin then
			u.remGroup(msg.chat.id)
			api.leaveChat(msg.chat.id)
		end
	end
end

function plugin.onCallbackQuery(msg, blocks)

	if not msg.from.admin then
		api.answerCallbackQuery(msg.cb_id, i18n("You are not allowed to use this button")) return
	end

	if blocks[1] == 'removewarn' then
		local user_id = blocks[2]
		if u.is_mod(msg.chat.id, user_id) and not u.is_owner(msg.chat.id, msg.from.id) then
			api.answerCallbackQuery(msg.cb_id, i18n("You are not allowed to use this button")) return
		end
		local num = db:hincrby('chat:'..msg.chat.id..':warns', user_id, -1) --add one warn
		local text, nmax
		if tonumber(num) < 0 then
			text = i18n("The number of warnings received by this user is already <i>zero</i>")
			db:hincrby('chat:'..msg.chat.id..':warns', user_id, 1) --restore the previouvs number
		else
			nmax = (db:hget('chat:'..msg.chat.id..':warnsettings', 'max')) or 3 --get the max num of warnings
			text = i18n("<b>Warn removed!</b> (%d/%d)"):format(tonumber(num), tonumber(nmax))
		local admin, name = u.getnames_complete(msg, blocks)
		u.logEvent('removewarn', msg,
			{admin = admin, user = name, user_id = user_id, rem = num})
		text = text .. i18n("\n(Admin: %s)"):format(u.getname_final(msg.from))
		end
		api.editMessageText(msg.chat.id, msg.message_id, text, 'html')
	elseif blocks[1] == 'remwarns' then
		local user_id = blocks[2]
		if u.is_mod(msg.chat.id, user_id) and not u.is_owner(msg.chat.id, msg.from.id) then
			api.answerCallbackQuery(msg.cb_id, i18n("You are not allowed to use this button")) return
		end
		local removed = {
			normal = db:hdel('chat:'..msg.chat.id..':warns', blocks[2]),
			media = db:hdel('chat:'..msg.chat.id..':mediawarn', blocks[2]),
			spam = db:hdel('chat:'..msg.chat.id..':spamwarns', blocks[2])
		}

		local admin, name = u.getnames_complete(msg, blocks)
		local text = i18n("The number of warnings received by this user has been <b>reset</b>, by %s"):format(name)
		api.editMessageText(msg.chat.id, msg.message_id, text:format(name), 'html')
		u.logEvent('nowarn', msg,
			{admin = admin, user = name, user_id = user_id, rem = removed})
	elseif blocks[1] == 'warn' then
		local user_id = blocks[2]
		if u.is_mod(msg.chat.id, user_id) and not u.is_owner(msg.chat.id, msg.from.id) then
			api.answerCallbackQuery(msg.cb_id, i18n("You are not allowed to use this button")) return
		end
		local name = user_id
		local hash = 'chat:'..msg.chat.id..':warns'
		local num = db:hincrby(hash, user_id, 1) --add one warn
		local nmax = (db:hget('chat:'..msg.chat.id..':warnsettings', 'max')) or 3 --get the max num of warnings
		local text, res, _, motivation, hammer_log
		num, nmax = tonumber(num), tonumber(nmax)
		local admin, name = u.getnames_complete(msg, blocks)
		if num >= nmax then
			local type = (db:hget('chat:'..msg.chat.id..':warnsettings', 'type')) or 'kick'
			--try to kick/ban
			text = i18n("%s <b>%s</b>: reached the max number of warnings (<code>%d/%d</code>)")
			if type == 'ban' then
				hammer_log = i18n('banned')
				text = text:format(name, hammer_log, num, nmax)
				res, _, motivation = api.banUser(msg.chat.id, user_id)
			elseif type == 'kick' then --kick
				hammer_log = i18n('kicked')
				text = text:format(name, hammer_log, num, nmax)
				res, _, motivation = api.kickUser(msg.chat.id, user_id)
			elseif type == 'mute' then --mute
				hammer_log = i18n('muted')
				text = text:format(name, hammer_log, num, nmax)
				res, _, motivation = api.muteUser(msg.chat.id, user_id)
			end
			--if kick/ban fails, send the motivation
			if not res then
				if not motivation then
					motivation = i18n("I can't kick this user.\n"
						.. "Probably I'm not an Admin, or the user is an Admin iself")
				end
				if num > nmax then db:hset(hash, user_id, nmax) end --avoid to have a number of warnings bigger than the max
				text = motivation
			else
				forget_user_warns(msg.chat.id, user_id)
			end
			--if the user reached the max num of warns, kick and send message
			api.editMessageText(msg.chat.id, msg.message_id, text, 'html')
			
			u.logEvent('warn', msg, {
				motivation = 'inline',
				admin = admin,
				user = name,
				user_id = user_id,
				hammered = hammer_log,
				warns = num,
				warnmax = nmax
			})
		else
			text = i18n("%s <b>has been warned</b> (<code>%d/%d</code>)"):format(name, num, nmax)
			api.editMessageText(msg.chat.id, msg.message_id, text, 'html')
			u.logEvent('warn', msg, {
				motivation = 'inline',
				warns = num,
				warnmax = nmax,
				admin = admin,
				user = name,
				user_id = user_id
			})
		end
	elseif blocks[1] == 'recache' then
		local missing_sec = tonumber(db:ttl('cache:chat:'..msg.target_id..':admins') or 0)
		local wait = 600
		if config.bot_settings.cache_time.adminlist - missing_sec < wait then
			local seconds_to_wait = wait - (config.bot_settings.cache_time.adminlist - missing_sec)
			api.answerCallbackQuery(msg.cb_id,i18n(
					"The adminlist has just been updated. You must wait 10 minutes from the last refresh (wait  %d seconds)"
				):format(seconds_to_wait), true)
		else
			db:del('cache:chat:'..msg.target_id..':admins')
			u.cache_adminlist(msg.target_id)
			local cached_admins = db:smembers('cache:chat:'..msg.target_id..':admins')
			local time = get_time_remaining(config.bot_settings.cache_time.adminlist)
			local text = i18n("📌 Status: `CACHED`\n⌛ ️Remaining: `%s`\n👥 Admins cached: `%d`")
				:format(time, #cached_admins)
			api.answerCallbackQuery(msg.cb_id, i18n("✅ Updated. Next update in %s"):format(time))
			api.editMessageText(msg.chat.id, msg.message_id, text, true, do_keyboard_cache(msg.target_id))
			--api.sendLog('#recache\nChat: '..msg.target_id..'\nFrom: '..msg.from.id)
		end
	elseif blocks[1] == 'kick' then
		local user_id = blocks[2]
		local chat_id = msg.chat.id
		local res, _, motivation = api.kickUser(chat_id, user_id)
		if not res then
			if not motivation then
				motivation = i18n("I can't kick this user.\n"
						.. "Either I'm not an admin, or the targeted user is!")
			end
			api.editMessageText(msg.chat.id, msg.message_id, motivation, 'html')
		else
			local admin, kicked = u.getnames_complete(msg, blocks)
			u.logEvent('kick', msg, {motivation = 'inline', admin = admin, user = kicked, user_id = user_id})
			api.editMessageText(msg.chat.id, msg.message_id, i18n("%s kicked %s!"):format(admin, kicked), 'html')
		end
	elseif blocks[1] == 'ban' then
		if not u.can(msg.chat.id, blocks[2], "can_restrict_members") then
			api.answerCallbackQuery(msg.cb_id, i18n("You are not allowed to use this button")) return
		end
		local user_id = blocks[2]
		local chat_id = msg.chat.id
		local res, _, motivation = api.banUser(chat_id, user_id)
		if not res then
			if not motivation then
				motivation = i18n("I can't kick this user.\n"
						.. "Either I'm not an admin, or the targeted user is!")
			end
			api.editMessageText(msg.chat.id, msg.message_id, motivation, 'html')
		else
			local admin, kicked = u.getnames_complete(msg, blocks)
			u.logEvent('ban', msg, {motivation = 'inline' , admin = admin, user = kicked, user_id = user_id})
			api.editMessageText(msg.chat.id, msg.message_id, i18n("%s banned %s!"):format(admin, kicked), 'html')
		end
	elseif blocks[1] == 'unban' then
		if not u.can(msg.chat.id, blocks[2], "can_restrict_members") then
			api.answerCallbackQuery(msg.cb_id, i18n("You are not allowed to use this button")) return
		end
		local user_id = blocks[2]
		local chat_id = msg.chat.id
		if u.is_admin(chat_id, user_id) then
			api.editMessageText(msg.chat.id, msg.message_id, i18n("_An admin can't be unbanned_"), 'html')
		else
			local result = api.getChatMember(chat_id, user_id)
			local text
			if result.result.status ~= 'kicked' then
				text = i18n("This user is not banned!")
			else
				api.unbanUser(chat_id, user_id)
				local admin, kicked = u.getnames_complete(msg, blocks)
				u.logEvent('unban', msg, {motivation = 'inline', admin = admin, user = kicked, user_id = user_id})
				text = i18n("%s unbanned by %s!"):format(kicked, admin)
			end
			api.editMessageText(msg.chat.id, msg.message_id, text, 'html')
		end
	end
end

plugin.triggers = {
	onTextMessage = {
		config.cmd..'(id)$',
		config.cmd..'(adminlist)$',
		config.cmd..'(status) (.+)$',
		config.cmd..'(status)$',
		config.cmd..'(cache)$',
		config.cmd..'(msglink)$',
		config.cmd..'(user)$',
		config.cmd..'(me)$',
		config.cmd..'(user) (.*)',
		config.cmd..'(leave)$'
	},
	onCallbackQuery = {
		'^###cb:userbutton:(remwarns):(%d+)$',
		'^###cb:userbutton:(removewarn):(%d+)$',
		'^###cb:userbutton:(warn):(%d+)$',
		'^###cb:userbutton:(kick):(%d+)$',
		'^###cb:userbutton:(ban):(%d+)$',
		'^###cb:userbutton:(unban):(%d+)$',
		'^###cb:(recache):'
	}
}

return plugin
