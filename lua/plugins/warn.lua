local config = require 'config'
local u = require 'utilities'
local api = require 'methods'
local db = require 'database'
local locale = require 'languages'
local i18n = locale.translate

local plugin = {}

local function doKeyboard_warn(user_id)
	local keyboard = {}
	keyboard.inline_keyboard = {{{text = i18n("Remove warn"), callback_data = 'removewarn:'..user_id}, 
	{text = i18n("Remove warnings"), callback_data = 'remwarns:'..user_id}}}

	return keyboard
end

local function forget_user_warns(chat_id, user_id)
	local removed = {
		normal = db:hdel('chat:'..chat_id..':warns', user_id) == 1 and 'v' or '⨯',
		media = db:hdel('chat:'..chat_id..':mediawarn', user_id) == 1 and 'v' or '⨯',
		spam = db:hdel('chat:'..chat_id..':spamwarns', user_id) == 1 and 'v' or '⨯'
	}

	return removed
end

local function get_motivation(msg)
	if msg.reply then
		return msg.text:match(config.cmd .. "warn%s+(.+)")
	else
		if msg.text:find(config.cmd.."warn%s+@%w[%w_]+%s+") then
			return msg.text:match(config.cmd.."warn%s+@%w[%w_]+%s+(.+)")
		elseif msg.text:find(config.cmd.."warn%s+%d+%s+") then
			return msg.text:match(config.cmd.."warn%s+%d+%s+(.+)")
		elseif msg.entities then
			return msg.text:match(config.cmd.."warn%s+%S-%s+(.+)")
		end
	end
end

function plugin.onTextMessage(msg, blocks)
	if msg.chat.type == 'private'
	or (msg.chat.type ~= 'private' and not u.is_allowed('hammer', msg.chat.id, msg.from)) then
		return
	end

	if blocks[1] == 'warnmax' then
		if not u.is_owner(msg.chat.id, msg.from.id) then return end
		local new, default, text, key
		local hash = 'chat:'..msg.chat.id..':warnsettings'
		if blocks[2] == 'media' then
			new = blocks[3]
			default = 2
			key = 'mediamax'
			text = i18n("Max number of warnings changed (media).\n")
		else
			key = 'max'
			new = blocks[2]
			default = 3
			text = i18n("Max number of warnings changed.\n")
		end
		local old = (db:hget(hash, key)) or default
		db:hset(hash, key, new)
		text = text .. i18n("*Old* value was %d\n*New* max is %d"):format(tonumber(old), tonumber(new))
		api.sendReply(msg, text, true)
		return
	end

	if blocks[1] == 'cleanwarn' then
		if not u.is_owner(msg.chat.id, msg.from.id) then return end
		local reply_markup =
		{
			inline_keyboard =
			{{{text = i18n('Yes'), callback_data = 'cleanwarns:yes'}, {text = i18n('No'), callback_data = 'cleanwarns:no'}}}
		}

		api.sendMessage(msg.chat.id,
			i18n('Do you want to continue and reset *all* the warnings received by *all* the users of the group?'),
			true, reply_markup)

		return
	end
	
	if not msg.reply
		and (not blocks[2] or (not blocks[2]:match('@[%w_]+$') and not blocks[2]:match('%d+$')
		and not msg.mention_id)) then
			
			api.sendReply(msg, i18n("Reply to an user or mention them by username or numerical ID"))
			return
	end
	local user_id = u.get_user_id(msg, blocks)

	if not user_id then
			api.sendReply(msg, i18n([[I've never seen this user before.
This command works by reply, username, user ID or text mention.
If you're using it by username and want to teach me who the user is, forward me one of his messages]]), true)
			return
		end
	--do not reply when...
	if (u.is_mod(msg.chat.id, user_id) and not
		u.is_owner(msg.chat.id, msg.from.id))
		or user_id == bot.id then
		return
	end

	if blocks[1] == 'nowarn' then
		local removed = forget_user_warns(msg.chat.id, user_id)
		local admin, user = u.getnames_complete(msg, blocks)
		local text = i18n(
			'Done! %s has been forgiven.\n<b>Warns found</b>: <i>normal warns %s, for media %s, spamwarns %s</i>'
			):format(user, removed.normal or 0, removed.media or 0, removed.spam or 0)
		api.sendReply(msg, text, 'html')
		u.logEvent('nowarn', msg, {admin = admin, user = user, user_id = user_id, rem = removed})
	end
	if blocks[1] == 'warn' or blocks[1] == 'sw' then
		local admin, name = u.getnames_complete(msg, blocks)
		local hash = 'chat:'..msg.chat.id..':warns'
		local num = db:hincrby(hash, user_id, 1) --add one warn
		local nmax = (db:hget('chat:'..msg.chat.id..':warnsettings', 'max')) or 3 --get the max num of warnings
		local text, res, _, motivation, hammer_log
		num, nmax = tonumber(num), tonumber(nmax)
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
			elseif type == 'mute' then --kick
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
			api.sendReply(msg, text, 'html')
			u.logEvent('warn', msg, {
				motivation = get_motivation(msg),
				admin = admin,
				user = name,
				user_id = user_id,
				hammered = hammer_log,
				warns = num,
				warnmax = nmax
			})
		else
			text = i18n("%s <b>has been warned</b> (<code>%d/%d</code>)"):format(name, num, nmax)
			local keyboard = doKeyboard_warn(user_id)
			if blocks[1] ~= 'sw' then api.sendMessage(msg.chat.id, text, 'html', keyboard) end
			u.logEvent('warn', msg, {
				motivation = get_motivation(msg),
				warns = num,
				warnmax = nmax,
				admin = admin,
				user = name,
				user_id = user_id
			})
		end
	end
end

function plugin.onCallbackQuery(msg, blocks)
	if not u.is_allowed('hammer', msg.chat.id, msg.from) then
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
		end
		local admin, name = u.getnames_complete(msg, blocks)
		text = text .. i18n("\n(Admin: %s)"):format(admin)
		api.editMessageText(msg.chat.id, msg.message_id, text, 'html')
		u.logEvent('removewarn', msg,
			{admin = admin, user = name, user_id = user_id, rem = num})
	end
	if blocks[1] == 'remwarns' then
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
		local text = i18n("The number of warnings received by this user has been <b>reset</b>, by %s"):format(admin)
		api.editMessageText(msg.chat.id, msg.message_id, text, 'html')
		u.logEvent('nowarn', msg,
			{admin = admin, user = name, user_id = user_id, rem = removed})
	end
	if blocks[1] == 'cleanwarns' then
		if blocks[2] == 'yes' then
			db:del('chat:'..msg.chat.id..':warns')
			db:del('chat:'..msg.chat.id..':mediawarn')
			db:del('chat:'..msg.chat.id..':spamwarns')
			api.editMessageText(msg.chat.id, msg.message_id,
				i18n('Done. All the warnings of this group have been erased by %s'):format(u.getname_final(msg.from)), 'html')
		else
			api.editMessageText(msg.chat.id, msg.message_id, i18n('_Action aborted_'), true)
		end
	end
end

plugin.triggers = {
	onTextMessage = {
		config.cmd..'(warnmax) (%d%d?)$',
		config.cmd..'(warnmax) (media) (%d%d?)$',
		config.cmd..'(warn)$',
		config.cmd..'(nowarn)s?$',
		--config.cmd..'(warn) (.*)$',
		config.cmd..'(warn) ([^%s]+)%s*(.-)$',
		config.cmd..'(cleanwarn)s?$',
		'[/!#](sw)%s',
		'[/!#](sw)$'
	},
	onCallbackQuery = {
		'^###cb:(resetwarns):(%d+)$',
		'^###cb:(remwarns):(%d+)$',
		'^###cb:(removewarn):(%d+)$',
		'^###cb:(cleanwarns):(%a%a%a?)$'
	}
}

return plugin
