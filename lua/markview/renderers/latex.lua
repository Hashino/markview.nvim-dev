local latex = {};

local symbols = require("markview.symbols");
local spec = require("markview.spec");
local utils = require("markview.utils");

latex.cache = {
	font_regions = {},
	style_regions = {
		superscripts = {},
		subscripts = {}
	},
};

local get_config = function (...)
	local _c = spec.get({ "latex", ... });

	if not _c or _c.enable == false then
		return;
	end

	return _c;
end

latex.__ns = {
	__call = function (self, key)
		return self[key] or self.default;
	end
}

latex.ns = {
	default = vim.api.nvim_create_namespace("markview/latex"),
};
setmetatable(latex.ns, latex.__ns)

latex.set_ns = function ()
	local ns_pref = get_config("use_seperate_ns");
	if not ns_pref then ns_pref = true; end

	local available = vim.api.nvim_get_namespaces();
	local ns_list = {
		["brackets"] = "markview/latex/brackets",
		["commands"] = "markview/latex/commands",
		["styles"] = "markview/latex/styles",
		["fonts"] = "markview/latex/fonts",
		["injections"] = "markview/latex/injections",
		["symbols"] = "markview/latex/symbols",
	};

	if ns_pref == true then
		for ns, name in pairs(ns_list) do
			if vim.list_contains(available, ns) == false then
				latex.ns[ns] = vim.api.nvim_create_namespace(name);
			end
		end
	end
end

latex.custom_config = function (config, value)
	if not config.custom or not value then
		return config;
	end

	for _, custom in ipairs(config.custom) do
		if custom.match_string and value:match(custom.match_string) then
			return vim.tbl_deep_extend("force", config, custom);
		end
	end

	return config;
end

latex.bracket = function (buffer, item)
	local config = get_config("brackets");

	if not config then
		return;
	end

	local range = item.range;

	--- Left parenthesis
	vim.api.nvim_buf_set_extmark(buffer, latex.ns("brackets"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_col = range.col_start + 1,
		conceal = ""
	});

	--- Right parenthesis
	vim.api.nvim_buf_set_extmark(buffer, latex.ns("brackets"), range.row_end, range.col_end - 1, {
		undo_restore = false, invalidate = true,
		end_col = range.col_end,
		conceal = ""
	});
end

latex.escaped = function (buffer, item)
	local config = get_config("escapes");

	if not config then
		return;
	end

	local range = item.range;

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("symbols"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_col = range.col_start + 1,
		conceal = ""
	});

	if not config.hl then
		return;
	end

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("symbols"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_row = range.row_end,
		end_col = range.col_end,

		hl_group = utils.set_hl(config.hl)
	});
end

latex.symbol = function (buffer, item)
	local config = get_config("symbols");

	if not config then
		return;
	elseif not item.name or not symbols.entries[item.name] then
		return;
	end

	local range = item.range;
	local within_font, font;

	for _, region in ipairs(latex.cache.font_regions) do
		if utils.within_range(region, range) then
			within_font = true;
			font = region.name;
			break;
		end
	end

	local _o, _h = "", nil;

	if
		item.style and get_config(item.style)
	then
		_o = symbols[item.style][item.name] or symbols.entries[item.name];
		_h = get_config(item.style, "hl");
	elseif
		get_config("fonts") and within_font == true and symbols.fonts[font] and
		symbols.fonts[font][item.name]
	then
		_o = symbols.fonts[font][item.name];
		_h = get_config("fonts", "hl");
	elseif symbols.entries[item.name] then
		_o = symbols.entries[item.name];
		_h = config.hl;
	else
		return;
	end


	vim.api.nvim_buf_set_extmark(buffer, latex.ns("symbols"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_col = range.col_end,
		conceal = "",

		virt_text_pos = "inline",
		virt_text = { { _o, utils.set_hl(_h) } },
		hl_mode = "combine"
	});
end

latex.font = function (buffer, item)
	local config = get_config("fonts");

	if not config then
		return;
	elseif not symbols.fonts[item.name] then
		return;
	end

	local range = item.range;
	table.insert(latex.cache.font_regions, vim.tbl_extend("force", item.range, { name = item.name }));

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("fonts"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_col = math.min(#item.text[1], range.font_end + 1),
		conceal = "",
	});

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("fonts"), range.row_end, range.col_end - 1, {
		undo_restore = false, invalidate = true,
		end_col = range.col_end,
		conceal = "",
	});
end

latex.word = function (buffer, item)
	local config = get_config("fonts");

	if not config then
		return;
	end

	local range = item.range;
	local within_font, font;
	local within_style, style;

	for _, region in ipairs(latex.cache.font_regions) do
		if utils.within_range(region, range) then
			within_font = true;
			font = region.name;
			break;
		end
	end

	for _, region in ipairs(latex.cache.style_regions.superscripts) do
		if utils.within_range(region, range) then
			within_style = true;
			style = "superscripts";
			break;
		end
	end

	for _, region in ipairs(latex.cache.style_regions.subscripts) do
		if utils.within_range(region, range) then
			within_style = true;
			style = "subscripts";
			break;
		end
	end

	local _o, _h = "", nil;

	if get_config(style) and within_style == true then
		for letter in item.text[1]:gmatch(".") do
			if symbols[style][letter] then
				_o = _o .. symbols[style][letter];
			else
				_o = _o .. letter;
			end
		end

		_h = get_config(style, "hl");
	elseif within_font == true and symbols.fonts[font] then
		for letter in item.text[1]:gmatch(".") do
			if symbols.fonts[font][letter] then
				_o = _o .. symbols.fonts[font][letter];
			else
				_o = _o .. letter;
			end
		end

		_h = get_config("fonts", "hl");
	else
		for letter in item.text[1]:gmatch(".") do
			if symbols.fonts.default[letter] then
				_o = _o .. symbols.fonts.default[letter];
			else
				_o = _o .. letter;
			end
		end

		_h = get_config("fonts", "hl")
	end

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("fonts"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_row = range.row_end,
		end_col = range.col_end,

		virt_text_pos = "overlay",
		virt_text = { { _o, utils.set_hl(_h) } },
		hl_mode = "combine"
	});
end

latex.subscript = function (buffer, item)
	local config = get_config("subscripts");

	if not config then
		return;
	end

	local range = item.range;

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("specials"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_col = range.col_start + (item.parenthasis and 2 or 1),
		conceal = "",

		virt_text_pos = "inline",
		virt_text = item.preview == false and { { "↓(", utils.set_hl(config.hl) } } or nil,

		hl_mode = "combine"
	});

	if item.parenthasis then
		if item.preview then
			table.insert(latex.cache.style_regions.subscripts, item.range);
		else
			vim.api.nvim_buf_set_extmark(buffer, latex.ns("specials"), range.row_start, range.col_start, {
				undo_restore = false, invalidate = true,
				end_row = range.row_end,
				end_col = range.col_end,

				hl_group = utils.set_hl(config.hl)
			});
		end

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("specials"), range.row_end, range.col_end - 1, {
			undo_restore = false, invalidate = true,
			end_col = range.col_end,
			conceal = "",

			virt_text_pos = "inline",
			virt_text = item.preview == false and { { ")", utils.set_hl(config.hl) } } or nil,

			hl_mode = "combine"
		});
	elseif symbols.superscripts[item.text[1]:sub(2)] then
		vim.api.nvim_buf_set_extmark(buffer, latex.ns("specials"), range.row_start, range.col_start + 1, {
			undo_restore = false, invalidate = true,
			virt_text_pos = "overlay",
			virt_text = { { symbols.subscripts[item.text[1]:sub(2)], utils.set_hl(config.hl) } },

			hl_mode = "combine"
		});
	end
end

latex.superscript = function (buffer, item)
	local config = get_config("superscripts");

	if not config then
		return;
	end

	local range = item.range;

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("specials"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_col = range.col_start + (item.parenthasis and 2 or 1),
		conceal = "",

		virt_text_pos = "inline",
		virt_text = item.preview == false and { { "↑(", utils.set_hl(config.hl) } } or nil,

		hl_mode = "combine"
	});

	if item.parenthasis then
		if item.preview then
			table.insert(latex.cache.style_regions.superscripts, item.range);
		else
			vim.api.nvim_buf_set_extmark(buffer, latex.ns("specials"), range.row_start, range.col_start, {
				undo_restore = false, invalidate = true,
				end_row = range.row_end,
				end_col = range.col_end,

				hl_group = utils.set_hl(config.hl)
			});
		end

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("specials"), range.row_end, range.col_end - 1, {
			undo_restore = false, invalidate = true,
			end_col = range.col_end,
			conceal = "",

			virt_text_pos = "inline",
			virt_text = item.preview == false and { { ")", utils.set_hl(config.hl) } } or nil,

			hl_mode = "combine"
		});
	elseif symbols.superscripts[item.text[1]:sub(2)] then
		vim.api.nvim_buf_set_extmark(buffer, latex.ns("specials"), range.row_start, range.col_start + 1, {
			undo_restore = false, invalidate = true,
			virt_text_pos = "overlay",
			virt_text = { { symbols.superscripts[item.text[1]:sub(2)], utils.set_hl(config.hl) } },

			hl_mode = "combine"
		});
	end
end

latex.inline = function (buffer, item)
	local range = item.range;
	local config = get_config("inlines");

	if not config then
		return;
	end

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_col = range.col_start + 1,
		conceal = "",

		virt_text_pos = "inline",
		virt_text = {
			{ config.corner_left or "", utils.set_hl(config.corner_left_hl or config.hl) },
			{ config.padding_left or "", utils.set_hl(config.padding_left_hl or config.hl) },
		},

		hl_mode = "combine"
	});

	if #item.text > 1 then
		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start, range.col_start + #item.text[1], {
			undo_restore = false, invalidate = true,

			virt_text_pos = "inline",
			virt_text = {
				{ config.padding_right or "", utils.set_hl(config.padding_right_hl or config.hl) }
			}
		});
	end

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_row = range.row_end,
		end_col = range.col_end,

		hl_group = utils.set_hl(config.hl),
	});

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_end, range.col_end - (item.closed and 1 or 0), {
		undo_restore = false, invalidate = true,
		end_col = range.col_end,
		conceal = "",

		virt_text_pos = "inline",
		virt_text = {
			{ config.padding_right or "", utils.set_hl(config.padding_right_hl or config.hl) },
			{ config.corner_right or "", utils.set_hl(config.corner_right_hl or config.hl) },
		},

		hl_mode = "combine"
	});

	if #item.text > 1 then
		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_end, 0, {
			undo_restore = false, invalidate = true,

			virt_text_pos = "inline",
			virt_text = {
				{ config.padding_left or "", utils.set_hl(config.padding_left_hl or config.hl) },
			}
		});
	end

	for l = 1, #item.text - 2 do
		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start + l, 0, {
			undo_restore = false, invalidate = true,

			virt_text_pos = "inline",
			virt_text = {
				{ config.padding_left or "", utils.set_hl(config.padding_left_hl or config.hl) },
			}
		});

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start + l, #item.text[l + 1], {
			undo_restore = false, invalidate = true,

			virt_text_pos = "inline",
			virt_text = {
				{ config.padding_right or "", utils.set_hl(config.padding_right_hl or config.hl) }
			}
		});
	end
end

latex.block = function (buffer, item)
	local range = item.range;
	local config;

	if get_config("inlines") and item.inline then
		config = get_config("inlines");

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start, range.col_start, {
			undo_restore = false, invalidate = true,
			end_col = range.col_start + 2,
			conceal = "",

			virt_text_pos = "inline",
			virt_text = {
				{ config.corner_left or "", utils.set_hl(config.corner_left_hl or config.hl) },
				{ config.padding_left or "", utils.set_hl(config.padding_left_hl or config.hl) },
			},

			hl_mode = "combine"
		});

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start, range.col_start + #item.text[1], {
			undo_restore = false, invalidate = true,

			virt_text_pos = "inline",
			virt_text = {
				{ config.padding_right or "", utils.set_hl(config.padding_right_hl or config.hl) }
			}
		});

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start, range.col_start, {
			undo_restore = false, invalidate = true,
			end_row = range.row_end,
			end_col = range.col_end,

			hl_group = utils.set_hl(config.hl),
		});

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_end, range.col_end - (item.closed and 2 or 0), {
			undo_restore = false, invalidate = true,
			end_col = range.col_end,
			conceal = "",

			virt_text_pos = "inline",
			virt_text = {
				{ config.padding_right or "", utils.set_hl(config.padding_right_hl or config.hl) },
				{ config.corner_right or "", utils.set_hl(config.corner_right_hl or config.hl) },
			},

			hl_mode = "combine"
		});

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_end, 0, {
			undo_restore = false, invalidate = true,

			virt_text_pos = "inline",
			virt_text = {
				{ config.padding_left or "", utils.set_hl(config.padding_left_hl or config.hl) },
			}
		});

		for l = 1, #item.text - 2 do
			vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start + l, math.min(#item.text[l + 1], 0), {
				undo_restore = false, invalidate = true,

				virt_text_pos = "inline",
				virt_text = {
					{ config.padding_left or "", utils.set_hl(config.padding_left_hl or config.hl) },
				}
			});

			vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start + l, #item.text[l + 1], {
				undo_restore = false, invalidate = true,

				virt_text_pos = "inline",
				virt_text = {
					{ config.padding_right or "", utils.set_hl(config.padding_right_hl or config.hl) }
				}
			});
		end
	elseif get_config("blocks") then
		config = get_config("blocks");

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start, range.col_start, {
			undo_restore = false, invalidate = true,
			end_col = range.col_start + 2,
			conceal = "",

			virt_text_pos = "right_align",
			virt_text = { { config.text or "", utils.set_hl(config.text_hl or config.hl) } },

			hl_mode = "combine",
			line_hl_group = utils.set_hl(config.hl)
		});

		vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_end, math.max(0, range.col_end - 2), {
			undo_restore = false, invalidate = true,
			end_col = range.col_end,
			conceal = "",

			line_hl_group = utils.set_hl(config.hl)
		});

		for l = 1, #item.text - 2 do
			vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start + l, math.min(#item.text[l + 1], range.col_start), {
				undo_restore = false, invalidate = true,

				virt_text_pos = "inline",
				virt_text = {
					{ string.rep(config.pad_char or "", config.pad_amount or 0), utils.set_hl(config.hl) }
				},

				line_hl_group = utils.set_hl(config.hl)
			});
		end
	end
end

latex.text = function (buffer, item)
	local config = get_config("texts");

	if not config then
		return;
	end

	local range = item.range;

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_start, range.col_start, {
		undo_restore = false, invalidate = true,
		end_col = range.col_start + #"\\text{",
		conceal = ""
	});

	vim.api.nvim_buf_set_extmark(buffer, latex.ns("injections"), range.row_end, range.col_end - 1, {
		undo_restore = false, invalidate = true,
		end_col = range.col_end,
		conceal = ""
	});
end

latex.render = function (buffer, content)
	latex.cache = {
		font_regions = {},
		style_regions = {
			superscripts = {},
			subscripts = {}
		},
	};

	for _, item in ipairs(content or {}) do
		pcall(latex[item.class:gsub("^latex_", "")], buffer, item);
		-- latex[item.class:gsub("^latex_", "")](buffer, item);
	end
end

latex.clear = function (buffer, ignore_ns, from, to)
	for name, ns in pairs(latex.ns) do
		if ignore_ns and vim.list_contains(ignore_ns, name) == false then
			vim.api.nvim_buf_clear_namespace(buffer, ns, from or 0, to or -1);
		end
	end
end

return latex;
