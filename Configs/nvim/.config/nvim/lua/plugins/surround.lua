return {

	"kylechui/nvim-surround", -- The plugin repository
	-- Optional: choose a desired version using a release tag or branch
	version = "*",     -- Use for stability; omit to use the latest features
	event = "VeryLazy", -- Load only when explicitly needed
	config = function()
		require("nvim-surround").setup({
			keymaps = {
				normal = "sa",
				normal_cur = "sl",
				normal_line = "sA",
				normal_cur_line = "sL",
				visual = "sa",
				visual_line = "sA",
				delete = "sd",
				change = "sr",
			},
		})
	end
}
